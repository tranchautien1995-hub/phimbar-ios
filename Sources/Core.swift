import Foundation
import CryptoKit

// The wire names and paths are those used by the supplied XemPhim 1.4 client.
// This is a new implementation; no Android executable or account data is bundled.
struct JSON {
    var raw: Any
    init(_ raw: Any = NSNull()) { self.raw = raw }
    init(data: Data) throws { raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
    subscript(_ key: String) -> JSON { JSON((raw as? [String: Any])?[key] ?? NSNull()) }
    var string: String { (raw as? String) ?? (raw as? NSNumber)?.stringValue ?? "" }
    var number: Double { (raw as? NSNumber)?.doubleValue ?? Double(string) ?? 0 }
    var bool: Bool { (raw as? Bool) ?? false }
    var array: [JSON] { (raw as? [Any] ?? []).map { JSON($0) } }
    var isNull: Bool { raw is NSNull }
}

struct Media: Identifiable, Equatable {
    let id, title, description, poster, backdrop, releaseDate, duration, type, contentRating: String
    let rating: Double
    let genres, countries, actors: [String]
    init(_ j: JSON) {
        id = j["id"].string; title = j["title"].string
        description = j["description"].string; poster = j["posterUrl"].string
        backdrop = j["backdropUrl"].string; releaseDate = j["releaseDate"].string
        duration = j["duration"].string; type = j["type"].string
        contentRating = j["contentRating"].string; rating = j["rating"].number
        genres = j["genres"].array.map(\.string); countries = j["countries"].array.map(\.string)
        actors = j["actors"].array.map(\.string)
    }
    var isSeries: Bool { type.uppercased() == "TV_SHOW" || type.lowercased() == "series" }
    var year: String { String(releaseDate.prefix(4)) }
    var summary: String { [year, isSeries ? "Series" : "Phim", duration, contentRating].filter { !$0.isEmpty }.joined(separator: "  ·  ") }
}
struct Category: Identifiable {
    let id, title: String
    let items: [Media]
    let ranges: [String: [Media]]
    init(_ j: JSON) {
        id = j["id"].string; title = j["title"].string
        var values: [String: [Media]] = [:]
        for key in ["day", "week", "month"] { let list = j["ranges"][key].array.map(Media.init); if !list.isEmpty { values[key] = list } }
        ranges = values
        let list = j["items"].array.map(Media.init); items = list.isEmpty ? (values["day"] ?? []) : list
    }
}
struct Season: Identifiable {
    let id: String; let number, count: Int
    init(_ j: JSON) { id = j["id"].string; number = Int(j["number"].number); count = Int(j["episodeCount"].number) }
}
struct Episode: Identifiable {
    let id, name, duration: String; let number: Int
    init(_ j: JSON) { id = j["id"].string; name = j["name"].string; duration = j["duration"].string; number = Int(j["number"].number) }
}
struct Subtitle: Identifiable {
    let id: String; let fileName, language, releaseName, uploader: String
    let isDefault: Bool; let likes, dislikes: Int
    init(_ j: JSON) {
        id = j["id"].string; fileName = j["fileName"].string; language = j["language"].string
        releaseName = j["releaseName"].string; uploader = j["uploader"].string
        isDefault = j["isDefault"].bool; likes = Int(j["likes"].number); dislikes = Int(j["dislikes"].number)
    }
    var label: String { [language, releaseName.isEmpty ? fileName : releaseName].filter { !$0.isEmpty }.joined(separator: " · ") }
}
struct Cue: Equatable { let start, end: Double; let text: String }

enum Wire {
    static let base = URL(string: "https://phimfly.com/api/tv/v1/")!
    static func segment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_~."))) ?? ""
    }
    static func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL {
        var c = URLComponents(string: base.absoluteString + path)!
        if !query.isEmpty { c.queryItems = query }
        return c.url!
    }
    static func safeURL(_ value: String) -> URL? {
        guard let u = URL(string: value), u.scheme?.lowercased() == "https", u.host != nil,
              u.user == nil, u.password == nil else { return nil }
        return u
    }
    static func rot(_ text: String, by shift: UInt32) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            let v = scalar.value, base: UInt32
            if (65...90).contains(v) { base = 65 } else if (97...122).contains(v) { base = 97 } else { return scalar }
            return UnicodeScalar(base + (v - base + shift) % 26)!
        }))
    }
    static func videoURL(_ value: String) -> URL? {
        guard let slash = value.lastIndex(of: "/") else { return nil }
        let tail = String(value[value.index(after: slash)...]), pieces = tail.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        var encoded = rot(String(pieces.first ?? ""), by: 6)
        while encoded.count % 4 != 0 { encoded += "=" }
        if pieces.count > 0, pieces.last != "m3u8", let decoded = Data(base64Encoded: encoded),
           let name = String(data: decoded, encoding: .isoLatin1), !name.isEmpty,
           name.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 127 }) {
            let suffix = pieces.count > 1 ? "." + pieces[1] : ""
            return safeURL(String(value[...slash]) + name + suffix)
        }
        return safeURL(value)
    }
    static func subtitleText(_ data: Data, fileName: String) throws -> String {
        guard let raw = String(data: data, encoding: .utf8) else { throw ClientError.message("Không đọc được phụ đề.") }
        if raw.contains("-->") || raw.contains("[Events]") { return raw }
        guard let bytes = Data(base64Encoded: raw.trimmingCharacters(in: .whitespacesAndNewlines)), bytes.count > 28 else {
            throw ClientError.message("Định dạng phụ đề chưa được hỗ trợ.")
        }
        let key = SymmetricKey(data: SHA256.hash(data: Data(("/watch/" + rot(fileName, by: 19)).utf8)))
        let text = try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: key)
        guard let decoded = String(data: text, encoding: .utf8) else { throw ClientError.message("Không đọc được phụ đề.") }
        return decoded
    }
    static func time(_ raw: String) -> Double {
        raw.replacingOccurrences(of: ",", with: ".").split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }
    static func cues(_ source: String) -> [Cue] {
        let lines = source.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        var result: [Cue] = [], i = 0
        let isASS = source.contains("[Events]")
        while i < lines.count {
            let line = lines[i]; i += 1
            if isASS, line.hasPrefix("Dialogue:") {
                let fields = line.dropFirst(9).split(separator: ",", maxSplits: 9, omittingEmptySubsequences: false)
                if fields.count == 10 {
                    let text = String(fields[9]).replacingOccurrences(of: "\\N", with: "\n")
                        .replacingOccurrences(of: "\\n", with: "\n")
                        .replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
                    result.append(Cue(start: time(String(fields[1])), end: time(String(fields[2])), text: clean(text)))
                }
            } else if line.contains("-->") {
                let pair = line.components(separatedBy: "-->")
                let start = time(pair[0].trimmingCharacters(in: .whitespaces)), end = time(pair[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0])
                var text: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty { text.append(lines[i]); i += 1 }
                if end > start { result.append(Cue(start: start, end: end, text: clean(text.joined(separator: "\n")))) }
            }
        }
        return result.sorted { $0.start < $1.start }
    }
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func clock(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "00:00" }
        let n = Int(value); return n >= 3600 ? String(format: "%d:%02d:%02d", n / 3600, n / 60 % 60, n % 60) : String(format: "%02d:%02d", n / 60, n % 60)
    }
}
enum ClientError: LocalizedError {
    case message(String)
    case accessDenied
    var errorDescription: String? { if case .message(let text) = self { return text }; return "Tài khoản chưa có quyền xem phim/tập này. Chọn Thuê lẻ để kiểm tra quyền trên Phimbar." }
}
