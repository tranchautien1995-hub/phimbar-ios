import SwiftUI
import AVKit
import Combine

struct PlayTarget: Identifiable {
    let id, title: String
    let resolveSeries: Bool
    var web: WebPlayback? = nil
    init(id: String, title: String, resolveSeries: Bool, web: WebPlayback? = nil) { self.id = id; self.title = title; self.resolveSeries = resolveSeries; self.web = web }
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
    @Published var rentalRequest: RentalTarget?
    @Published var embeddedSubtitles: [AVMediaSelectionOption] = []
    var pictureInPicture: AVPictureInPictureController?
    private var statusObserver: NSKeyValueObservation?, periodicObserver: Any?, endObserver: NSObjectProtocol?, failedObserver: NSObjectProtocol?
    private var currentID = "", ticket = UUID(), subtitleTicket = UUID(), pendingPosition = 0.0, prepared = false
    private var lastSave = Date.distantPast, saveBusy = false, didPlay = false
    private var pendingSave: (id: String, seconds: Int)?
    private var originalTargetID = ""
    private var lastPresence = Date()
    private weak var session: Session?
    private var subtitleTask: Task<Void, Never>?
    private var cueCache: [String: [Cue]] = [:]
    private var webCues: [String: [Cue]] = [:]
    private var webAsset: RentalAsset?
    private var webMode = false
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
    func load(_ target: PlayTarget, session: Session) async {
        let sameTarget = originalTargetID == target.id
        await saveProgress()
        let currentTicket = UUID(); ticket = currentTicket; loading = true; error = ""; prepared = false
        subtitleTicket = UUID(); subtitleTask?.cancel()
        let keep = sameTarget && position > 0 ? position : nil
        if !sameTarget {
            position = 0; duration = 0; didPlay = false; cues = []; caption = ""
            subtitles = []; selectedSubtitle = ""; cueCache.removeAll()
        }
        originalTargetID = target.id
        webAsset?.close(); webAsset = nil; rentalRequest = nil; webCues.removeAll()
        webMode = target.web != nil
        player.pause(); self.session = session; title = target.title
        do {
            var id = target.id
            if target.resolveSeries && target.web == nil {
                let play = try await session.get("titles/" + Wire.segment(id) + "/play")
                id = play["episode"]["id"].string
                guard !id.isEmpty else { throw ClientError.message("Chưa có tập phim để phát.") }
                title = target.title + " · Mùa \(Int(play["seasonNumber"].number)) · Tập \(Int(play["episode"]["number"].number))"
            }
            let root = "titles/" + Wire.segment(id)
            let source: JSON
            if let web = target.web { source = JSON(["url": web.url.absoluteString]) }
            else {
                do { source = try await session.get(root + "/video", query: [URLQueryItem(name: "server", value: server)]) }
                catch ClientError.accessDenied { rentalRequest = RentalTarget(id: id, title: title); throw ClientError.message("Bạn có thể thuê lẻ đúng phim/tập qua Phimbar ở màn vừa mở.") }
            }
            guard currentTicket == ticket else { return }
            guard let url = Wire.videoURL(source["url"].string) else { throw ClientError.message("Nguồn video không hợp lệ hoặc chưa hỗ trợ HTTPS.") }
            var watch: JSON?
            if target.web == nil { watch = try? await session.get(root + "/watch") }
            try Task.checkCancellation(); guard currentTicket == ticket else { return }
            currentID = id; didPlay = false; lastSave = Date(); nextEpisode = nil
            let webPosition = target.web?.time ?? 0
            let local = UserDefaults.standard.double(forKey: "resume." + id)
            if target.web != nil { pendingPosition = keep ?? (UserDefaults.standard.object(forKey: "resume." + id) != nil ? local : webPosition) }
            else { pendingPosition = keep ?? (watch?["time"].isNull == false ? watch!["time"].number : local) }
            if let next = watch?["nextEpisode"], !next["episode"]["id"].string.isEmpty {
                nextEpisode = PlayTarget(id: next["episode"]["id"].string, title: target.title + " · Tập \(Int(next["episode"]["number"].number))", resolveSeries: false)
            }
            let asset: AVURLAsset
            if let web = target.web { let loader = RentalAsset(source: web); webAsset = loader; asset = try await loader.start() }
            else { asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "XemPhim/1.4"]]) }
            let item = AVPlayerItem(asset: asset); statusObserver = nil
            statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self = self, currentTicket == self.ticket else { return }
                    if item.status == .failed { self.loading = false; self.error = "Không phát được nguồn này trên iOS. Thử máy chủ khác." }
                    if item.status == .readyToPlay && !self.prepared {
                        self.prepared = true; self.loading = false
                        self.embeddedSubtitles = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)?.options ?? []
                        let total = item.duration.seconds, saved = self.pendingPosition
                        let safe = total.isFinite && total > 0 ? min(max(0, saved), max(0, total - 1)) : max(0, saved)
                        self.player.seek(to: CMTime(seconds: safe, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                            Task { @MainActor in guard let self = self, currentTicket == self.ticket, finished else { return }; self.player.play() }
                        }
                    }
                }
            }
            player.replaceCurrentItem(with: item)
            subtitleTask?.cancel()
            if let web = target.web, !web.subtitles.isEmpty {
                subtitles = web.subtitles.enumerated().map { index, sub in
                    let id = "web-\(index)"; webCues[id] = sub.cues
                    return Subtitle(JSON(["id": id, "language": sub.language, "releaseName": sub.label, "isDefault": index == 0]))
                }
                if let first = subtitles.first(where: { ["vi", "vie"].contains($0.language.lowercased()) }) ?? subtitles.first { await choose(first) }
            } else if target.web == nil { subtitleTask = Task { [weak self] in await self?.loadSubtitles(id: id, ticket: currentTicket, session: session) } }
            else { subtitles = []; cues = []; subtitleError = "Chọn phụ đề trên website và đợi phụ đề tải trước khi chuyển sang trình phát app." }
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
        if let item = player.currentItem, let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) { item.select(nil, in: group) }
        selectedSubtitle = subtitle.id; subtitleError = ""
        if let loaded = webCues[subtitle.id] { cues = loaded; return }
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
        guard !subtitle.id.hasPrefix("web-") else { return }
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
        if !webMode && playing && Date().timeIntervalSince(lastPresence) >= 30 {
            lastPresence = Date(); let token = ticket
            Task {
                guard let session = session else { return }
                if let status = try? await session.get("watching-elsewhere"), token == ticket, status["watchingElsewhere"].bool {
                    player.pause(); error = "Tài khoản đang xem ở thiết bị khác. Dừng phiên đó rồi chọn Thử lại."; playing = false
                }
            }
        }
    }
    func saveProgress() async {
        guard didPlay, prepared, player.currentItem?.error == nil, position.isFinite, position > 1, !currentID.isEmpty else { return }
        let id = currentID, seconds = Int(position)
        UserDefaults.standard.set(position, forKey: "resume." + id)
        if webMode { return } // Website session may differ from native API session.
        pendingSave = (id, seconds)
        guard let session = session, !saveBusy else { return }; saveBusy = true
        let token = session.login?.token
        // Do not substitute a load failure or a fresh zero for the saved watch time.
        // Closing or changing servers never waits for the progress network request.
        Task {
            defer { saveBusy = false }
            while let pending = pendingSave {
                pendingSave = nil
                guard session.login?.token == token else { break }
                do { _ = try await session.data("titles/" + Wire.segment(pending.id) + "/progress", method: "PUT", body: ["time": pending.seconds]) } catch { /* Local fallback retained. */ }
            }
        }
    }
    func seek(by seconds: Double) { let target = min(max(0, position + seconds), duration > 0 ? duration : Double.greatestFiniteMagnitude); player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) }
    func seek(to seconds: Double) { guard seconds.isFinite else { return }; player.seek(to: CMTime(seconds: max(0, min(seconds, duration)), preferredTimescale: 600)) }
    func selectEmbedded(_ option: AVMediaSelectionOption?) {
        guard let item = player.currentItem, let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        subtitleTicket = UUID(); selectedSubtitle = "off"; cues = []; caption = ""
        item.select(option, in: group)
    }
    func attach(_ layer: AVPlayerLayer) {
        guard pictureInPicture == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        pictureInPicture = AVPictureInPictureController(playerLayer: layer)
    }
    func togglePiP() {
        guard let pip = pictureInPicture, pip.isPictureInPicturePossible else { session?.message = "PiP chưa sẵn sàng cho video này."; return }
        if pip.isPictureInPictureActive { pip.stopPictureInPicture() } else { pip.startPictureInPicture() }
    }
    func stop() async {
        await saveProgress(); prepared = false; didPlay = false; ticket = UUID(); subtitleTicket = UUID(); subtitleTask?.cancel(); player.pause(); statusObserver = nil
        if pictureInPicture?.isPictureInPictureActive == true { pictureInPicture?.stopPictureInPicture() }; pictureInPicture = nil
        webAsset?.close(); webAsset = nil
        if let token = periodicObserver { player.removeTimeObserver(token); periodicObserver = nil }
        if let token = endObserver { NotificationCenter.default.removeObserver(token); endObserver = nil }
        if let token = failedObserver { NotificationCenter.default.removeObserver(token); failedObserver = nil }
        player.replaceCurrentItem(with: nil)
    }
}

final class VideoSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var ready: ((AVPlayerLayer) -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { ready?(videoLayer) } }
}
struct NativeVideo: UIViewRepresentable {
    let playback: Playback
    var fill = false
    func makeUIView(context: Context) -> VideoSurface {
        let view = VideoSurface(); view.backgroundColor = .black; view.clipsToBounds = true
        view.videoLayer.player = playback.player; view.videoLayer.videoGravity = .resizeAspect
        view.ready = { [weak playback] layer in Task { @MainActor in playback?.attach(layer) } }
        return view
    }
    func updateUIView(_ view: VideoSurface, context: Context) { view.videoLayer.player = playback.player; view.videoLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect }
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
    @State var seeking = false
    @State var seekPosition = 0.0
    @State var rental: RentalTarget?
    @State var fullscreen = false
    @State var controlsShown = true
    @State var fill = false
    var showControls: Bool { !fullscreen || controlsShown }
    func toggleFullscreen() { fullscreen.toggle(); controlsShown = !fullscreen }
    var actualTarget: PlayTarget { active ?? target }
    var body: some View {
        VStack(spacing: 0) {
            if showControls {
            HStack(spacing: 14) {
                Button { Task { await playback.stop(); dismiss() } } label: { Image(systemName: "chevron.down").font(.title2).padding(10) }.accessibilityLabel("Đóng trình phát")
                Text(playback.title.isEmpty ? actualTarget.title : playback.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Button { toggleFullscreen() } label: { Image(systemName: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").padding(10) }.accessibilityLabel(fullscreen ? "Thoát toàn màn hình" : "Toàn màn hình")
            }.padding(.horizontal, 10).background(Color.navy)
            }
            ZStack(alignment: .bottom) {
                NativeVideo(playback: playback, fill: fill).clipped().contentShape(Rectangle())
                    .onTapGesture(count: 2) { fullscreen = true; controlsShown = false; fill.toggle() }
                    .onTapGesture { if fullscreen { controlsShown.toggle() } }
                if !playback.caption.isEmpty {
                    Text(playback.caption).font(.system(size: size, weight: .semibold)).foregroundColor(yellow ? .yellow : .white)
                        .multilineTextAlignment(.center).padding(8).background(background ? Color.black.opacity(0.65) : Color.clear).cornerRadius(4)
                        .shadow(color: .black, radius: 2).padding(.horizontal, 24).padding(.bottom, bottom).allowsHitTesting(false)
                }
                if playback.loading { ProgressView("Đang tải video…").padding(24).background(Color.black.opacity(0.8)).cornerRadius(12).frame(maxHeight: .infinity) }
                if !playback.error.isEmpty { Failure(message: playback.error) { reload += 1 }.background(Color.navy.opacity(0.95)).frame(maxHeight: .infinity) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped().background(Color.black)
            if showControls {
            HStack(spacing: 12) {
                Button {
                    if playback.player.rate != 0 { playback.player.pause() } else { playback.player.play() }
                } label: { Image(systemName: playback.playing ? "pause.fill" : "play.fill").font(.title3).frame(width: 28, height: 36) }.accessibilityLabel(playback.playing ? "Tạm dừng" : "Phát")
                Text(Wire.clock(playback.position)).font(.caption.monospacedDigit())
                Slider(value: Binding(get: { seeking ? seekPosition : playback.position }, set: { seekPosition = $0 }), in: 0...max(1, playback.duration), onEditingChanged: { editing in
                    if editing { seekPosition = playback.position; seeking = true } else { seeking = false; playback.seek(to: seekPosition) }
                }).tint(.accent).disabled(playback.duration <= 0)
                Text(Wire.clock(playback.duration)).font(.caption.monospacedDigit())
            }.padding(.horizontal, 18).padding(.top, 8).background(Color.navy)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 25) {
                    Button { toggleFullscreen() } label: { Label(fullscreen ? "Thu nhỏ" : "Toàn màn hình", systemImage: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }
                    Button { fill.toggle() } label: { Label(fill ? "Vừa khung" : "Lấp đầy", systemImage: "viewfinder") }.accessibilityHint("Lấp đầy có thể cắt bớt mép hình")
                    Button { playback.seek(by: -15) } label: { Label("15s", systemImage: "gobackward.15") }
                    Button { playback.seek(by: 15) } label: { Label("15s", systemImage: "goforward.15") }
                    if actualTarget.web == nil { Menu { ForEach(["1", "2", "3"], id: \.self) { server in Button("Máy chủ " + server) { playback.server = server } } } label: { Label("Máy chủ " + playback.server, systemImage: "server.rack") } }
                    else { Button { rental = RentalTarget(id: actualTarget.id, title: playback.title) } label: { Label("Đổi máy chủ", systemImage: "server.rack") } }
                    Button { subtitlesOpen = true } label: { Label("CC", systemImage: "captions.bubble") }
                    Button { rental = RentalTarget(id: actualTarget.id, title: playback.title) } label: { Label("Thuê lẻ", systemImage: "cart") }
                    Button { playback.togglePiP() } label: { Label("PiP", systemImage: "pip") }
                    Menu { ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { rate in Button(String(format: "%.2g×", rate)) { playback.player.rate = Float(rate) } } } label: { Label("Tốc độ", systemImage: "speedometer") }
                    if let next = playback.nextEpisode { Button { active = next } label: { Label("Tập tiếp", systemImage: "forward.end.fill") } }
                }.font(.system(size: 13, weight: .medium)).padding(18)
            }.background(Color.navy)
            }
        }.foregroundColor(.white).background(Color.black.ignoresSafeArea())
            .ignoresSafeArea(fullscreen && !controlsShown ? .all : [], edges: .all)
            .statusBar(hidden: fullscreen)
            .overlay(alignment: .topTrailing) {
                if fullscreen && !controlsShown {
                    Button { fullscreen = false; controlsShown = true } label: { Image(systemName: "arrow.down.right.and.arrow.up.left").font(.title3).foregroundColor(.white).padding(14).background(Color.black.opacity(0.55)).clipShape(Circle()) }.accessibilityLabel("Thoát toàn màn hình").padding(.top, 44).padding(.trailing, 44)
                }
            }
            .onAppear {
                #if UI_PREVIEW
                if CommandLine.arguments.contains("--fixture-fullscreen") { fullscreen = true; controlsShown = false; fill = true }
                #endif
            }
            .task {
                #if UI_PREVIEW
                if CommandLine.arguments.contains("--fixture-fullscreen") { try? await Task.sleep(nanoseconds: 25_000_000_000); if !Task.isCancelled { controlsShown = true } }
                #endif
            }
            .task(id: "\(actualTarget.id)-\(playback.server)-\(reload)") { await playback.load(actualTarget, session: session) }
            .onDisappear { Task { await playback.stop() } }
            .onChange(of: scenePhase) { phase in if phase != .active { Task { await playback.saveProgress() } } }
            .sheet(isPresented: $subtitlesOpen) { SubtitlePanel(playback: playback) }
            .onChange(of: playback.rentalRequest?.id) { value in if value != nil { rental = playback.rentalRequest } }
            .sheet(item: $rental) { target in RentalSheet(target: target) { source in rental = nil; active = source; reload += 1 } }
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
                    if !playback.embeddedSubtitles.isEmpty {
                        Button("Tắt phụ đề trong video") { playback.selectEmbedded(nil) }
                        ForEach(Array(playback.embeddedSubtitles.enumerated()), id: \.offset) { _, option in Button("Trong video · " + option.displayName) { playback.selectEmbedded(option) } }
                    }
                    Button("Tắt phụ đề ngoài") { Task { await playback.choose(nil) } }
                    ForEach(playback.subtitles) { sub in
                        VStack(alignment: .leading, spacing: 10) {
                            Button { Task { await playback.choose(sub) } } label: { HStack { Text(sub.label).font(.system(size: 14)); Spacer(); if playback.selectedSubtitle == sub.id { Image(systemName: "checkmark") } } }
                            HStack { Text(sub.uploader).font(.caption).foregroundColor(.secondary); Spacer(); Button("👍 \(sub.likes)") { Task { await playback.vote(sub, value: "like") } }.buttonStyle(.borderless); Button("👎 \(sub.dislikes)") { Task { await playback.vote(sub, value: "dislike") } }.buttonStyle(.borderless) }
                        }
                    }
                    if !playback.subtitleError.isEmpty { Text(playback.subtitleError).font(.footnote).foregroundColor(.orange) }
                    Button("Tải lại danh sách phụ đề") { Task { await playback.reloadSubtitles() } }
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
