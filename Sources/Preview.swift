// Only compiled into the simulator QA app. No fixture login or API shortcut in IPA.
#if UI_PREVIEW
import Foundation
enum Preview {
    static var enabled: Bool { CommandLine.arguments.contains { $0.hasPrefix("--fixture-") } }
    static var playerVerified = false
    static let movie: [String: Any] = ["id": "qa-movie", "title": "Phim kiểm tra", "description": "Dữ liệu tổng hợp để kiểm tra bố cục, nút bấm và phụ đề. Không phải nội dung từ tài khoản.", "type": "MOVIE", "releaseDate": "2026-11-21", "duration": "10 phút", "rating": 8.1, "genres": ["Dữ liệu kiểm tra"], "actors": ["Kiểm tra giao diện"], "posterUrl": "", "backdropUrl": ""]
    static var series: [String: Any] { var value = movie; value["id"] = "qa-series"; value["title"] = "Series kiểm tra"; value["type"] = "TV_SHOW"; return value }
    static func response(_ path: String) throws -> Data {
        let result: Any
        switch path {
        case "home": result = [["id": "continue", "title": "Tiếp tục xem · Dữ liệu kiểm tra", "items": [movie, series]], ["id": "popular", "title": "Thịnh hành", "items": [series, movie]]]
        case "titles/qa-movie", "titles/qa-series": result = path.hasSuffix("series") ? series : movie
        case "titles/qa-movie/video": result = ["url": "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", "server": "1"]
        case "titles/qa-movie/watch": result = ["time": 40, "duration": 600]
        case "titles/qa-movie/subtitles": result = ["subtitles": [["id": 1, "fileName": "fixture.srt", "language": "vi", "releaseName": "Phụ đề kiểm tra", "isDefault": true, "likes": 0, "dislikes": 0]]]
        case "subtitles/1/file": return Data("1\n00:00:00,000 --> 01:00:00,000\nPhụ đề tiếng Việt · Dữ liệu kiểm tra\n".utf8)
        case "titles/qa-movie/progress": result = [:] as [String: String]
        case "titles/qa-movie/my-list", "titles/qa-series/my-list": result = ["status": "wishlist"]
        case "watching-elsewhere": result = ["watchingElsewhere": false]
        default: throw ClientError.message("Chưa có dữ liệu kiểm tra cho màn này.")
        }
        return try JSONSerialization.data(withJSONObject: result)
    }
}
#endif
