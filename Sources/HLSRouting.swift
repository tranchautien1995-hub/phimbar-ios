import Foundation

enum HLSRouting {
    static func proxy(_ url: URL, playlist: Bool = false) -> URL {
        let code = Data(url.absoluteString.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return URL(string: "xemphim-hls://resource/" + code + (playlist || url.pathExtension.lowercased() == "m3u8" ? "/index.m3u8" : "/data.bin"))!
    }
    static func remote(_ url: URL) -> URL? {
        guard url.scheme == "xemphim-hls", let code = url.path.split(separator: "/").first else { return nil }
        var base = String(code).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base.count % 4 != 0 { base += "=" }
        guard let data = Data(base64Encoded: base), let text = String(data: data, encoding: .utf8) else { return nil }
        return Wire.safeURL(text)
    }
    static func rewrite(_ text: String, base: URL) -> String {
        func mapped(_ raw: String, playlist: Bool = false) -> String {
            guard let absolute = URL(string: raw, relativeTo: base)?.absoluteURL,
                  let remote = Wire.videoURL(absolute.absoluteString) else { return raw }
            return proxy(remote, playlist: playlist).absoluteString
        }
        let expression = try! NSRegularExpression(pattern: "URI=\"([^\"]+)\"")
        var nextPlaylist = false
        return text.components(separatedBy: "\n").map { line in
            if !line.isEmpty && !line.hasPrefix("#") { let value = mapped(line.trimmingCharacters(in: .whitespacesAndNewlines), playlist: nextPlaylist); nextPlaylist = false; return value }
            if line.hasPrefix("#EXT-X-STREAM-INF:") { nextPlaylist = true }
            var result = line
            for match in expression.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
                if let range = Range(match.range(at: 1), in: result) { result.replaceSubrange(range, with: mapped(String(result[range]), playlist: line.hasPrefix("#EXT-X-MEDIA:") || line.hasPrefix("#EXT-X-I-FRAME-STREAM-INF:"))) }
            }
            return result
        }.joined(separator: "\n")
    }
    static func cookieHeader(_ cookies: [HTTPCookie], for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let eligible = cookies.filter { c in
            let domain = c.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return !domain.isEmpty && (host == domain || (c.domain.hasPrefix(".") && host.hasSuffix("." + domain))) && url.path.hasPrefix(c.path) && (c.expiresDate == nil || c.expiresDate! > Date()) && (!c.isSecure || url.scheme == "https")
        }
        return eligible.isEmpty ? nil : HTTPCookie.requestHeaderFields(with: eligible)["Cookie"]
    }
}
