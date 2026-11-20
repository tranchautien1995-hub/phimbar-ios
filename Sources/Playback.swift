import SwiftUI
import AVKit
import Combine

struct PlayTarget: Identifiable {
    let id, title: String
    let resolveSeries: Bool
    init(id: String, title: String, resolveSeries: Bool) { self.id = id; self.title = title; self.resolveSeries = resolveSeries }
    init(media: Media) { id = media.id; title = media.title; resolveSeries = media.isSeries }
}
@MainActor final class Playback: ObservableObject {
    let player = AVPlayer()
    @Published var loading = true
    @Published var error = ""
    @Published var subtitleError = ""
    @Published var title = ""
    @Published var server = "1"
    @Published var playing = false
    @Published var subtitles: [Subtitle] = []
    @Published var selectedSubtitle = ""
    @Published var cues: [Cue] = []
    @Published var caption = ""
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var nextEpisode: PlayTarget?
    private var statusObserver: NSKeyValueObservation?, periodicObserver: Any?, endObserver: NSObjectProtocol?, failedObserver: NSObjectProtocol?
    private var currentID = "", ticket = UUID(), subtitleTicket = UUID(), pendingPosition = 0.0, prepared = false
    private var lastSave = Date.distantPast, saveBusy = false, didPlay = false
    private weak var session: Session?
    private var subtitleTask: Task<Void, Never>?
    private var cueCache: [String: [Cue]] = [:]
    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        periodicObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in self?.tick(time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in guard let self = self, note.object as? AVPlayerItem === self.player.currentItem else { return }; self.playing = false; await self.saveProgress() }
        }
        failedObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in guard let self = self, note.object as? AVPlayerItem === self.player.currentItem else { return }; self.error = "Video bị gián đoạn. Hãy thử máy chủ khác hoặc tải lại."; self.playing = false }
        }
    }
    func load(_ target: PlayTarget, session: Session, switching: Bool = false) async {
        if switching { await saveProgress() }
        let currentTicket = UUID(); ticket = currentTicket; loading = true; error = ""; prepared = false
        let keep = switching && position > 0 ? position : nil
        player.pause(); self.session = session; title = target.title
        do {
            var id = target.id
            if target.resolveSeries {
                let play = try await session.get("titles/" + Wire.segment(id) + "/play")
                id = play["episode"]["id"].string
                guard !id.isEmpty else { throw ClientError.message("Chưa có tập phim để phát.") }
                title = target.title + " · Mùa \(Int(play["seasonNumber"].number)) · Tập \(Int(play["episode"]["number"].number))"
            }
            let root = "titles/" + Wire.segment(id)
            let source = try await session.get(root + "/video", query: [URLQueryItem(name: "server", value: server)])
            guard currentTicket == ticket else { return }
            guard let url = Wire.videoURL(source["url"].string) else { throw ClientError.message("Nguồn video không hợp lệ hoặc chưa hỗ trợ HTTPS.") }
            let watch = try? await session.get(root + "/watch")
            try Task.checkCancellation(); guard currentTicket == ticket else { return }
            currentID = id; didPlay = false; lastSave = Date(); nextEpisode = nil
            pendingPosition = keep ?? (watch?["time"].isNull == false ? watch!["time"].number : UserDefaults.standard.double(forKey: "resume." + id))
            if let next = watch?["nextEpisode"], !next["episode"]["id"].string.isEmpty {
                nextEpisode = PlayTarget(id: next["episode"]["id"].string, title: target.title + " · Tập \(Int(next["episode"]["number"].number))", resolveSeries: false)
            }
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "XemPhim/1.4"]])
            let item = AVPlayerItem(asset: asset); statusObserver = nil
            statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self = self, currentTicket == self.ticket else { return }
                    if item.status == .failed { self.loading = false; self.error = "Không phát được nguồn này trên iOS. Thử máy chủ khác." }
                    if item.status == .readyToPlay && !self.prepared {
                        self.prepared = true; self.loading = false
                        let total = item.duration.seconds, saved = self.pendingPosition
                        let safe = total.isFinite && total > 0 ? min(max(0, saved), max(0, total - 1)) : max(0, saved)
                        self.player.seek(to: CMTime(seconds: safe, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                            Task { @MainActor in guard let self = self, currentTicket == self.ticket, finished else { return }; self.player.play() }
                        }
                    }
                }
            }
            player.replaceCurrentItem(with: item)
            subtitleTask?.cancel(); subtitleTask = Task { [weak self] in await self?.loadSubtitles(id: id, ticket: currentTicket, session: session) }
        } catch { if !Task.isCancelled && currentTicket == ticket { loading = false; self.error = error.localizedDescription } }
    }
    private func loadSubtitles(id: String, ticket: UUID, session: Session) async {
        subtitleError = ""
        do {
            let j = try await session.get("titles/" + Wire.segment(id) + "/subtitles")
            guard ticket == self.ticket else { return }
            subtitles = j["subtitles"].array.map(Subtitle.init)
            if let selected = subtitles.first(where: { $0.id == selectedSubtitle }) { await choose(selected) }
            else if selectedSubtitle.isEmpty, let first = subtitles.first(where: { $0.isDefault }) ?? subtitles.first(where: { ["vi", "vie", "vietnamese"].contains($0.language.lowercased()) }) { await choose(first) }
        } catch { if !Task.isCancelled && ticket == self.ticket { subtitleError = "Không tải được danh sách phụ đề. Bạn có thể thử lại trong CC." } }
    }
    func choose(_ subtitle: Subtitle?) async {
        let token = UUID(); subtitleTicket = token
        guard let subtitle = subtitle else { selectedSubtitle = "off"; cues = []; caption = ""; return }
        selectedSubtitle = subtitle.id; subtitleError = ""
        if let cached = cueCache[subtitle.id] { cues = cached; return }
        cues = []; caption = ""
        do {
            guard let session = session else { return }
            let bytes = try await session.data("subtitles/" + Wire.segment(subtitle.id) + "/file")
            let parsed = try await Task.detached(priority: .userInitiated) { () throws -> [Cue] in
                guard bytes.count <= 8 * 1024 * 1024 else { throw ClientError.message("Tệp phụ đề quá lớn.") }
                return Wire.cues(try Wire.subtitleText(bytes, fileName: subtitle.fileName))
            }.value
            guard token == subtitleTicket else { return }
            guard !parsed.isEmpty else { throw ClientError.message("Phụ đề chưa có nội dung hiển thị.") }
            if cueCache.count >= 4 { cueCache.removeAll() }; cueCache[subtitle.id] = parsed; cues = parsed
        } catch { if !Task.isCancelled && token == subtitleTicket { subtitleError = "Không đọc được phụ đề này. Hãy chọn bản khác." } }
    }
    func reloadSubtitles() async { guard let session = session, !currentID.isEmpty else { return }; await loadSubtitles(id: currentID, ticket: ticket, session: session) }
    func vote(_ subtitle: Subtitle, value: String) async {
        do { guard let session = session else { return }; let result = try await session.get("subtitles/" + Wire.segment(subtitle.id) + "/vote", method: "POST", body: ["isLike": value == "like"]); subtitles = result["subtitles"].array.map(Subtitle.init) } catch { session?.report(error) }
    }
    private func tick(_ seconds: Double) {
        guard prepared, seconds.isFinite, seconds >= 0 else { return }
        position = seconds; let total = player.currentItem?.duration.seconds ?? 0; duration = total.isFinite ? total : 0
        playing = player.rate != 0; if playing { didPlay = true }
        let delay = UserDefaults.standard.double(forKey: "subtitle.delay"), t = seconds - delay
        var lo = 0, hi = cues.count
        while lo < hi { let middle = (lo + hi) / 2; if cues[middle].start <= t { lo = middle + 1 } else { hi = middle } }
        let active = cues[max(0, lo - 8)..<lo].filter { $0.start <= t && $0.end > t }.map(\.text).joined(separator: "\n")
        if caption != active { caption = active }
        #if UI_PREVIEW
        if Preview.enabled && !Preview.playerVerified && playing && position >= 41 && !caption.isEmpty {
            Preview.playerVerified = true
            let record: [String: Any] = ["ready": true, "playing": true, "position": position, "savedStart": pendingPosition, "subtitleRendered": true, "cueCount": cues.count]
            if let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
               let bytes = try? JSONSerialization.data(withJSONObject: record, options: .prettyPrinted) { try? bytes.write(to: folder.appendingPathComponent("player-verification.json")) }
        }
        #endif
        if playing && Date().timeIntervalSince(lastSave) >= 15 { lastSave = Date(); Task { await saveProgress() } }
    }
    func saveProgress() async {
        guard didPlay, prepared, player.currentItem?.error == nil, position.isFinite, position > 1, !currentID.isEmpty, !saveBusy else { return }
        let id = currentID, seconds = Int(position)
        UserDefaults.standard.set(position, forKey: "resume." + id)
        guard let session = session else { return }; saveBusy = true; defer { saveBusy = false }
        // Do not substitute a load failure or a fresh zero for the saved watch time.
        do { _ = try await session.data("titles/" + Wire.segment(id) + "/progress", method: "PUT", body: ["time": seconds]) } catch { /* Local fallback retained; a progress error must not interrupt video. */ }
    }
    func seek(by seconds: Double) { let target = min(max(0, position + seconds), duration > 0 ? duration : Double.greatestFiniteMagnitude); player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) }
    func stop() async {
        await saveProgress(); prepared = false; didPlay = false; ticket = UUID(); subtitleTicket = UUID(); subtitleTask?.cancel(); player.pause(); statusObserver = nil
        if let token = periodicObserver { player.removeTimeObserver(token); periodicObserver = nil }
        if let token = endObserver { NotificationCenter.default.removeObserver(token); endObserver = nil }
        if let token = failedObserver { NotificationCenter.default.removeObserver(token); failedObserver = nil }
        player.replaceCurrentItem(with: nil)
    }
}

struct NativeVideo: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let v = AVPlayerViewController(); v.player = player; v.showsPlaybackControls = true; v.allowsPictureInPicturePlayback = true; v.videoGravity = .resizeAspect; return v
    }
    func updateUIViewController(_ view: AVPlayerViewController, context: Context) { view.player = player }
}
@MainActor struct PlaybackScreen: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    @StateObject var playback = Playback()
    let target: PlayTarget
    @State var subtitlesOpen = false
    @State var reload = 0
    @AppStorage("subtitle.size") var size = 22.0
    @AppStorage("subtitle.bottom") var bottom = 50.0
    @AppStorage("subtitle.background") var background = true
    @AppStorage("subtitle.yellow") var yellow = false
    @State var active: PlayTarget?
    var actualTarget: PlayTarget { active ?? target }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { Task { await playback.stop(); dismiss() } } label: { Image(systemName: "chevron.down").font(.title2).padding(10) }.accessibilityLabel("Đóng trình phát")
                Text(playback.title.isEmpty ? actualTarget.title : playback.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).background(Color.navy)
            ZStack(alignment: .bottom) {
                NativeVideo(player: playback.player)
                if !playback.caption.isEmpty {
                    Text(playback.caption).font(.system(size: size, weight: .semibold)).foregroundColor(yellow ? .yellow : .white)
                        .multilineTextAlignment(.center).padding(8).background(background ? Color.black.opacity(0.65) : Color.clear).cornerRadius(4)
                        .shadow(color: .black, radius: 2).padding(.horizontal, 24).padding(.bottom, bottom).allowsHitTesting(false)
                }
                if playback.loading { ProgressView("Đang tải video…").padding(24).background(Color.black.opacity(0.8)).cornerRadius(12).frame(maxHeight: .infinity) }
                if !playback.error.isEmpty { Failure(message: playback.error) { reload += 1 }.background(Color.navy.opacity(0.95)).frame(maxHeight: .infinity) }
            }.background(Color.black)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 25) {
                    Button { playback.seek(by: -15) } label: { Label("15s", systemImage: "gobackward.15") }
                    Button { playback.seek(by: 15) } label: { Label("15s", systemImage: "goforward.15") }
                    Menu { ForEach(["1", "2", "3"], id: \.self) { server in Button("Máy chủ " + server) { playback.server = server } } } label: { Label("Máy chủ " + playback.server, systemImage: "server.rack") }
                    Button { subtitlesOpen = true } label: { Label("CC", systemImage: "captions.bubble") }
                    Menu { ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { rate in Button(String(format: "%.2g×", rate)) { playback.player.rate = Float(rate) } } } label: { Label("Tốc độ", systemImage: "speedometer") }
                    if let next = playback.nextEpisode { Button { active = next } label: { Label("Tập tiếp", systemImage: "forward.end.fill") } }
                }.font(.system(size: 13, weight: .medium)).padding(18)
            }.background(Color.navy)
        }.foregroundColor(.white).background(Color.black.ignoresSafeArea())
            .task(id: "\(actualTarget.id)-\(playback.server)-\(reload)") { await playback.load(actualTarget, session: session, switching: playback.position > 0 && active == nil) }
            .onDisappear { Task { await playback.stop() } }
            .onChange(of: scenePhase) { phase in if phase != .active { Task { await playback.saveProgress() } } }
            .sheet(isPresented: $subtitlesOpen) { SubtitlePanel(playback: playback) }
    }
}
struct SubtitlePanel: View {
    @ObservedObject var playback: Playback
    @AppStorage("subtitle.size") var size = 22.0
    @AppStorage("subtitle.bottom") var bottom = 50.0
    @AppStorage("subtitle.delay") var delay = 0.0
    @AppStorage("subtitle.background") var background = true
    @AppStorage("subtitle.yellow") var yellow = false
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            Form {
                Section("Phụ đề") {
                    Button("Tắt phụ đề ngoài") { Task { await playback.choose(nil) } }
                    ForEach(playback.subtitles) { sub in
                        VStack(alignment: .leading, spacing: 10) {
                            Button { Task { await playback.choose(sub) } } label: { HStack { Text(sub.label).font(.system(size: 14)); Spacer(); if playback.selectedSubtitle == sub.id { Image(systemName: "checkmark") } } }
                            HStack { Text(sub.uploader).font(.caption).foregroundColor(.secondary); Spacer(); Button("👍 \(sub.likes)") { Task { await playback.vote(sub, value: "like") } }.buttonStyle(.borderless); Button("👎 \(sub.dislikes)") { Task { await playback.vote(sub, value: "dislike") } }.buttonStyle(.borderless) }
                        }
                    }
                    if !playback.subtitleError.isEmpty { Text(playback.subtitleError).font(.footnote).foregroundColor(.orange) }
                    Button("Tải lại danh sách phụ đề") { Task { await playback.reloadSubtitles() } }
                    Text("Phụ đề tích hợp trong video nằm trong nút phụ đề của trình phát iOS.").font(.caption).foregroundColor(.secondary)
                }
                Section("Hiển thị") {
                    Text("Cỡ chữ: \(Int(size))"); Slider(value: $size, in: 12...44, step: 1)
                    Text("Vị trí từ cạnh dưới: \(Int(bottom))"); Slider(value: $bottom, in: 10...220, step: 5)
                    Toggle("Nền đen", isOn: $background); Toggle("Chữ màu vàng", isOn: $yellow)
                    Stepper("Lệch thời gian: \(String(format: "%+.1f", delay)) giây", value: $delay, in: -30...30, step: 0.5)
                    Button("Về mặc định") { size = 22; bottom = 50; delay = 0; background = true; yellow = false }
                }
            }.navigationTitle("Phụ đề · CC").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
        }.navigationViewStyle(.stack).preferredColorScheme(.dark)
    }
}
