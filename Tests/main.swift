import Foundation
import CryptoKit

func check(_ condition: @autoclosure () -> Bool, _ label: String) { if !condition() { fatalError(label) }; print("PASS: " + label) }
let fixture = JSON(["id": "movie-1", "title": "Phim Việt", "type": "TV_SHOW", "rating": 8.5, "releaseDate": "2026-11-21", "posterUrl": "https://example.com/p.jpg", "genres": ["Drama"]])
let media = Media(fixture)
check(media.id == "movie-1" && media.isSeries && media.year == "2026" && media.genres == ["Drama"], "Media wire fields, series and year")
check(Wire.safeURL("https://user:secret@example.com/a") == nil, "Credential-bearing video URL rejected")
check(Wire.safeURL("http://example.com/a") == nil, "HTTPS required")
check(Wire.segment("a/b?token#") == "a%2Fb%3Ftoken%23", "Episode ID encoded as one segment")
let trending = Category(JSON(["id": "trending", "title": "Thịnh hành", "ranges": ["day": [fixture.raw], "week": [fixture.raw]]]))
check(trending.items.count == 1 && trending.ranges["week"]?.count == 1, "Trending range fallback and weekly data")
let clear = "playlist.m3u8"
let encoded = Wire.rot(Data(clear.utf8).base64EncodedString(), by: 20)
check(Wire.videoURL("https://example.com/" + encoded)?.absoluteString == "https://example.com/playlist.m3u8", "HLS filename transformation round trip")
check(Wire.videoURL("https://example.com/master.m3u8?token=1")?.absoluteString == "https://example.com/master.m3u8?token=1", "Signed HLS URL preserved")
let srt = "1\n00:01:00,500 --> 00:01:02,000\n<i>Xin chào</i>\n\n2\n00:01:03,000 --> 00:01:05,000\nDòng 1\nDòng 2\n"
let cues = Wire.cues(srt)
check(cues.count == 2 && cues[0].start == 60.5 && cues[0].text == "Xin chào" && cues[1].text == "Dòng 1\nDòng 2", "SRT timing, tags, Unicode and multiline")
let vtt = "WEBVTT\n\n00:00:01.000 --> 00:00:03.500 align:center\nXin chào\n"
check(Wire.cues(vtt).first?.end == 3.5, "WebVTT cue settings")
let ass = "[Events]\nDialogue: 0,0:00:01.20,0:00:03.40,Default,,0,0,0,,{\\i1}Xin chào\\NViệt Nam"
check(Wire.cues(ass).first?.text == "Xin chào\nViệt Nam", "ASS timestamps and dialogue")
let fileName = "episode-vi.srt", key = SymmetricKey(data: SHA256.hash(data: Data(("/watch/" + Wire.rot(fileName, by: 19)).utf8)))
let encrypted = try AES.GCM.seal(Data(srt.utf8), using: key).combined!
let decrypted = try Wire.subtitleText(Data(encrypted.base64EncodedString().utf8), fileName: fileName)
check(decrypted == srt, "Authorized subtitle payload AES-GCM interoperability")
var rejected = false
do { _ = try Wire.subtitleText(Data(encrypted.base64EncodedString().utf8), fileName: "wrong.srt") } catch { rejected = true }
check(rejected, "Subtitle authentication failure detected")
check(Wire.clock(6300) == "1:45:00" && Wire.clock(.nan) == "00:00", "Resume display and invalid time")
print("All protocol checks passed.")

let signed = URL(string: "https://cdn.example.com/media/master.m3u8?key=demo")!
check(HLSRouting.remote(HLSRouting.proxy(signed)) == signed, "Web HLS route preserves signed URL")
let playlist = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\"\nsegment.ts\n"
let mapped = HLSRouting.rewrite(playlist, base: signed)
check(mapped.contains("xemphim-hls://resource/") && !mapped.contains("URI=\"key.bin\""), "Playlist segments and key URI mapped")
let cookie = HTTPCookie(properties: [.domain: ".phimbar.com", .path: "/", .name: "session", .value: "fixture"])!
check(HLSRouting.cookieHeader([cookie], for: URL(string: "https://phimbar.com/watch/a")!) != nil, "Website cookie matches own origin")
check(HLSRouting.cookieHeader([cookie], for: URL(string: "https://cdn.example.com/a")!) == nil && HLSRouting.cookieHeader([cookie], for: URL(string: "https://evilphimbar.com/a")!) == nil, "Website cookie not forwarded to CDN or suffix impersonation")

let unpadded = encoded.replacingOccurrences(of: "=", with: "")
check(Wire.videoURL("https://example.com/" + unpadded)?.absoluteString == "https://example.com/playlist.m3u8", "Unpadded source filename compatibility")
