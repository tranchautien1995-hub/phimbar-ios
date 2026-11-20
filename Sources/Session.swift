import Foundation
import Combine
import Security

struct Login: Codable { let token, name, email: String }
enum LoginKeychain {
    static let service = "vn.onnstream.phimbar.ios.native-session"
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "session"] }
    static func read() -> Login? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Login.self, from: data)
    }
    static func save(_ login: Login?) throws {
        if login == nil { SecItemDelete(query as CFDictionary); return }
        let data = try JSONEncoder().encode(login!), status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw ClientError.message("Không lưu được phiên đăng nhập trong Keychain.") }; return
        }
        guard status == errSecSuccess else { throw ClientError.message("Không cập nhật được phiên đăng nhập.") }
    }
}

@MainActor final class Session: ObservableObject {
    @Published var login = LoginKeychain.read()
    @Published var message: String?
    let http: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 45
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        http = URLSession(configuration: config)
    }
    func data(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: [String: Any]? = nil, authenticated: Bool = true) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: Wire.endpoint(path, query: query)); request.httpMethod = method
        request.setValue("XemPhim/1.4", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let token = login?.token, !token.isEmpty else { throw ClientError.message("Bạn cần đăng nhập.") }
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if let body = body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await http.data(for: request); try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw ClientError.message("Không nhận được phản hồi máy chủ.") }
        switch response.statusCode {
        case 200...299: return data
        case 401:
            if authenticated { try? LoginKeychain.save(nil); login = nil }
            throw ClientError.message(authenticated ? "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại." : "Email hoặc mật khẩu không đúng.")
        case 402, 403: throw ClientError.message("Tài khoản chưa có quyền xem nội dung này. Kiểm tra VIP hoặc quyền thuê phim trên Phimbar.")
        case 404: throw ClientError.message("Không tìm thấy nội dung này.")
        case 429: throw ClientError.message("Có quá nhiều yêu cầu. Vui lòng đợi một phút rồi thử lại.")
        case 400, 422: throw ClientError.message("Thông tin gửi chưa hợp lệ. Kiểm tra lại và thử lại.")
        default: throw ClientError.message("Máy chủ chưa phản hồi được (\(response.statusCode)). Thử lại sau.")
        }
    }
    func get(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: [String: Any]? = nil, authenticated: Bool = true) async throws -> JSON {
        let bytes = try await data(path, query: query, method: method, body: body, authenticated: authenticated)
        return bytes.isEmpty ? JSON() : try JSON(data: bytes)
    }
    func accept(_ result: JSON) throws {
        let token = result["sessionId"].string
        guard !token.isEmpty else { throw ClientError.message("Máy chủ chưa cấp phiên đăng nhập.") }
        let value = Login(token: token, name: result["user"]["name"].string, email: result["user"]["email"].string)
        try LoginKeychain.save(value); login = value
    }
    func signIn(email: String, password: String) async throws {
        let result = try await get("auth/login", method: "POST", body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password], authenticated: false)
        try accept(result)
    }
    func logout() async throws {
        _ = try await data("auth/session", method: "DELETE")
        try LoginKeychain.save(nil); login = nil
    }
    func report(_ error: Error) { if !(error is CancellationError) && (error as NSError).code != NSURLErrorCancelled { message = error.localizedDescription } }
}
