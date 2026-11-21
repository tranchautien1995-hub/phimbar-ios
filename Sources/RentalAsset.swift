import Foundation
import AVFoundation
import Network

// Loopback-only HLS adapter for URLs the authenticated website actually supplied.
// The nonce prevents unrelated local requests; API bearer tokens are never used.
final class RentalAsset: NSObject, URLSessionTaskDelegate {
    private let source: WebPlayback
    private let queue = DispatchQueue(label: "XemPhim.web-media")
    private var listener: NWListener?
    private var base = ""
    private let nonce = UUID().uuidString
    private var connections: [UUID: NWConnection] = [:]
    private var tasks: [UUID: URLSessionDataTask] = [:]
    private lazy var http: URLSession = {
        let c = URLSessionConfiguration.ephemeral; c.httpCookieStorage = nil; c.urlCredentialStorage = nil
        c.httpMaximumConnectionsPerHost = 3; c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()
    init(source: WebPlayback) { self.source = source; super.init() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, Wire.safeURL(url.absoluteString) != nil else { completionHandler(nil); return }
        var next = request; next.setValue(nil, forHTTPHeaderField: "Cookie")
        if url.host == source.page.host { next.setValue(HLSRouting.cookieHeader(source.cookies, for: url), forHTTPHeaderField: "Cookie") }
        completionHandler(next)
    }
    func start() async throws -> AVURLAsset {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let server = try NWListener(using: parameters); listener = server
        let url: URL = try await withCheckedThrowingContinuation { continuation in
            var finished = false
            server.stateUpdateHandler = { [weak self] state in
                guard let self = self, !finished else { return }
                switch state {
                case .ready:
                    guard let port = server.port else { finished = true; continuation.resume(throwing: ClientError.message("Không mở được trình phát nội bộ.")); return }
                    self.base = "http://127.0.0.1:\(port.rawValue)/" + self.nonce + "/"
                    let remote = Wire.videoURL(self.source.url.absoluteString) ?? self.source.url
                    let code = HLSRouting.proxy(remote, playlist: !["mp4", "m4v", "mov"].contains(remote.pathExtension.lowercased())).path.dropFirst()
                    finished = true; continuation.resume(returning: URL(string: self.base + code)!)
                case .failed, .cancelled: finished = true; continuation.resume(throwing: ClientError.message("Không khởi tạo được nguồn phát web."))
                default: break
                }
            }
            server.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            server.start(queue: queue)
        }
        try Task.checkCancellation(); return AVURLAsset(url: url)
    }
    func close() { queue.async { self.listener?.cancel(); self.listener = nil; self.tasks.values.forEach { $0.cancel() }; self.tasks.removeAll(); self.connections.values.forEach { $0.cancel() }; self.connections.removeAll(); self.http.invalidateAndCancel() } }
    private func accept(_ connection: NWConnection) {
        let id = UUID(); connections[id] = connection; connection.start(queue: queue); read(connection, id: id, accumulated: Data())
    }
    private func read(_ connection: NWConnection, id: UUID, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            guard let self = self else { return }; var all = accumulated; if let data = data { all.append(data) }
            if all.count > 16384 || error != nil { self.end(id); return }
            guard let text = String(data: all, encoding: .utf8), text.contains("\r\n\r\n") else {
                if complete { self.end(id) } else { self.read(connection, id: id, accumulated: all) }; return
            }
            self.handle(text, id: id)
        }
    }
    private func handle(_ text: String, id: UUID) {
        let lines = text.components(separatedBy: "\r\n"), first = (lines.first ?? "").components(separatedBy: " ")
        guard first.count == 3, ["GET", "HEAD"].contains(first[0]), first[1].hasPrefix("/" + nonce + "/") else { send(id, status: 403, body: Data()); return }
        let path = String(first[1].dropFirst(nonce.count + 2))
        guard let virtual = URL(string: "xemphim-hls://resource/" + path), let remote = HLSRouting.remote(virtual) else { send(id, status: 400, body: Data()); return }
        var request = URLRequest(url: remote); request.httpMethod = first[0]
        request.setValue(source.page.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(source.userAgent.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: ""), forHTTPHeaderField: "User-Agent")
        // Redirects carry no manually supplied Cookie header. Only same-origin website
        // resources may use website cookies; signed CDN media does not receive them.
        if remote.host == source.page.host { request.setValue(HLSRouting.cookieHeader(source.cookies, for: remote), forHTTPHeaderField: "Cookie") }
        for line in lines where line.lowercased().hasPrefix("range:") {
            let value = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            if value.range(of: "^bytes=[0-9]+-[0-9]*$", options: .regularExpression) != nil && !path.hasSuffix("index.m3u8") { request.setValue(value, forHTTPHeaderField: "Range") }
        }
        let task = http.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }; self.queue.async {
                self.tasks.removeValue(forKey: id)
                guard error == nil, let response = response as? HTTPURLResponse, [200, 206].contains(response.statusCode), var data = data, data.count <= 48 * 1024 * 1024 else { self.send(id, status: 502, body: Data()); return }
                var mime = response.mimeType ?? "application/octet-stream", headers: [String: String] = [:]
                if data.starts(with: Data("#EXTM3U".utf8)), let text = String(data: data, encoding: .utf8) {
                    guard data.count < 4 * 1024 * 1024 else { self.send(id, status: 502, body: Data()); return }
                    let rewritten = HLSRouting.rewrite(text, base: response.url ?? remote).replacingOccurrences(of: "xemphim-hls://resource/", with: self.base)
                    data = Data(rewritten.utf8); mime = "application/vnd.apple.mpegurl"
                } else {
                    if data.first == 0x47 { mime = "video/mp2t" }
                    for key in ["Content-Range", "Accept-Ranges"] { if let value = response.value(forHTTPHeaderField: key) { headers[key] = value } }
                }
                self.send(id, status: response.statusCode, body: first[0] == "HEAD" ? Data() : data, mime: mime, extra: headers, length: first[0] == "HEAD" ? response.expectedContentLength : Int64(data.count))
            }
        }
        tasks[id] = task; task.resume()
    }
    private func send(_ id: UUID, status: Int, body: Data, mime: String = "text/plain", extra: [String: String] = [:], length: Int64? = nil) {
        guard let connection = connections[id] else { return }
        var header = "HTTP/1.1 \(status) \(status == 200 ? "OK" : status == 206 ? "Partial Content" : "Error")\r\nContent-Type: \(mime)\r\nContent-Length: \(max(0, length ?? Int64(body.count)))\r\nConnection: close\r\nCache-Control: no-store\r\n"
        for (key, value) in extra where !value.contains("\r") && !value.contains("\n") { header += key + ": " + value + "\r\n" }
        var packet = Data((header + "\r\n").utf8); packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { [weak self] _ in self?.queue.async { self?.end(id) } })
    }
    private func end(_ id: UUID) { tasks.removeValue(forKey: id)?.cancel(); connections.removeValue(forKey: id)?.cancel() }
}
