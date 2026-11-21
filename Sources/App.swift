import SwiftUI
import SafariServices
import UIKit

extension Color {
    init(hex: UInt32) { self.init(red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255) }
    static let navy = Color(hex: 0x091224), surface = Color(hex: 0x182135), raised = Color(hex: 0x263045), accent = Color(hex: 0xe50914)
}
struct MainButton: ButtonStyle {
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 16, weight: .semibold)).padding(.horizontal, 20).padding(.vertical, 13)
            .foregroundColor(.white).background(secondary ? Color.raised : Color.accent)
            .cornerRadius(8).opacity(configuration.isPressed ? 0.65 : 1)
    }
}
struct Artwork: View {
    var address: String
    var body: some View {
        AsyncImage(url: Wire.safeURL(address)) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else { Rectangle().fill(Color.raised).overlay(Image(systemName: "film").font(.title).foregroundColor(.white.opacity(0.25))) }
        }.clipped().accessibilityHidden(true)
    }
}
struct Failure: View {
    let message: String; var retry: () -> Void
    var body: some View { VStack(spacing: 18) { Image(systemName: "wifi.exclamationmark").font(.largeTitle); Text(message).multilineTextAlignment(.center); Button("Thử lại", action: retry).buttonStyle(MainButton()) }.padding(30).frame(maxWidth: .infinity) }
}
struct SafariPage: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ view: SFSafariViewController, context: Context) {}
}

@main @MainActor struct XemPhimApp: App {
    @StateObject var session = Session()
    init() {
        let appearance = UINavigationBarAppearance(); appearance.configureWithOpaqueBackground(); appearance.backgroundColor = UIColor(Color.navy)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = appearance; UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = .white
    }
    var body: some Scene {
        WindowGroup {
            NavigationView {
                root
                    .background(Color.navy.ignoresSafeArea()).navigationBarHidden(true)
            }.navigationViewStyle(.stack).environmentObject(session).preferredColorScheme(.dark).tint(.accent)
                .alert("XemPhim", isPresented: Binding(get: { session.message != nil }, set: { if !$0 { session.message = nil } })) { Button("Đóng", role: .cancel) {} } message: { Text(session.message ?? "") }
        }
    }
    @ViewBuilder var root: some View {
        #if UI_PREVIEW
        if CommandLine.arguments.contains("--fixture-web-player") { PlaybackScreen(target: PlayTarget(id: "qa-movie", title: "Tập đã thuê · Kiểm tra", resolveSeries: false, web: WebPlayback(url: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!, page: URL(string: "https://phimbar.com/watch/qa-movie")!, time: 40, cookies: [], subtitles: [WebSubtitle(label: "Tiếng Việt", language: "vi", cues: [Cue(start: 0, end: 3600, text: "Phụ đề tập đã thuê · Dữ liệu kiểm tra")])], userAgent: "XemPhim/1.4"))) }
        else if CommandLine.arguments.contains("--fixture-details") { DetailsScreen(initial: Media(JSON(Preview.movie))) }
        else if CommandLine.arguments.contains("--fixture-player") || CommandLine.arguments.contains("--fixture-fullscreen") { PlaybackScreen(target: PlayTarget(media: Media(JSON(Preview.movie)))) }
        else { regular }
        #else
        regular
        #endif
    }
    @ViewBuilder var regular: some View { if session.login != nil { Shell() } else { LoginScreen() } }
}

struct LoginScreen: View {
    @EnvironmentObject var session: Session
    @State var email = ""
    @State var password = ""
    @State var busy = false
    @State var byCode = false
    @State var code = ""
    @State var codeNote = ""
    @State var refresh = 0
    @State var web = false
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 28)
                    Text("XemPhim").font(.system(size: 40, weight: .heavy)).foregroundColor(.accent)
                    Text("Đăng nhập để tiếp tục").font(.title2.bold())
                    if byCode {
                        Text(code.isEmpty ? "······" : code).font(.system(size: 38, weight: .bold, design: .monospaced)).tracking(7).textSelection(.enabled)
                        Text(codeNote).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                        Button("Lấy mã mới") { refresh += 1 }.buttonStyle(MainButton(secondary: true))
                    } else {
                        VStack(spacing: 16) {
                            TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.username).textInputAutocapitalization(.never).disableAutocorrection(true)
                                .padding(16).background(Color.raised).cornerRadius(8).accessibilityIdentifier("login.email")
                            SecureField("Mật khẩu", text: $password).textContentType(.password).padding(16).background(Color.raised).cornerRadius(8).accessibilityIdentifier("login.password")
                            Button { Task { busy = true; defer { busy = false }; do { try await session.signIn(email: email, password: password); password = "" } catch { session.report(error) } } } label: {
                                HStack { if busy { ProgressView().tint(.white) }; Text(busy ? "Đang đăng nhập…" : "Đăng nhập").frame(maxWidth: .infinity) }
                            }.buttonStyle(MainButton()).disabled(busy || email.isEmpty || password.isEmpty)
                        }
                    }
                    Button(byCode ? "Đăng nhập bằng email" : "Đăng nhập bằng mã") { byCode.toggle() }.foregroundColor(.white)
                    Text("Dùng tài khoản của dịch vụ. Kết nối tới phimfly.com như app XemPhim 1.4.").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    Button("Mở trang Phimbar") { web = true }.font(.footnote).foregroundColor(.secondary)
                    Spacer(minLength: 28)
                }.padding(28).frame(maxWidth: 440).frame(maxWidth: .infinity, minHeight: geo.size.height)
            }.scrollDismissesKeyboardCompat()
        }.sheet(isPresented: $web) { SafariPage(url: URL(string: "https://phimbar.com/")!) }
            .task(id: "\(byCode)-\(refresh)") {
                guard byCode else { return }; code = ""; codeNote = "Đang lấy mã đăng nhập…"
                do {
                    let value = try await session.get("auth/device-code", method: "POST", body: [:], authenticated: false)
                    code = value["code"].string; let token = value["pollToken"].string
                    guard !code.isEmpty, !token.isEmpty else { throw ClientError.message("Chưa nhận được mã đăng nhập.") }
                    codeNote = "Nhập mã này tại mục đăng nhập TV trên website của dịch vụ. Mã sẽ tự kiểm tra sau vài giây."
                    let expires = Date().addingTimeInterval(min(900, max(30, value["expiresInSeconds"].number)))
                    let interval = max(3, value["intervalSeconds"].number)
                    while Date() < expires {
                        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)); try Task.checkCancellation()
                        let poll = try await session.get("auth/device-code/poll", method: "POST", body: ["pollToken": token], authenticated: false)
                        if !poll["sessionId"].string.isEmpty { try session.accept(poll); return }
                        if poll["status"].string == "expired" { break }
                    }
                    codeNote = "Mã đã hết hạn. Bấm Lấy mã mới."
                } catch { if !Task.isCancelled { codeNote = error.localizedDescription } }
            }
    }
}
extension View {
    // iOS 15 has no scrollDismissesKeyboard API.
    func scrollDismissesKeyboardCompat() -> some View { self }
}

enum Page: String, CaseIterable { case home = "Trang chủ", series = "Series", movies = "Phim", search = "Tìm kiếm", lists = "Danh sách của tôi", account = "Tài khoản" }
struct Shell: View {
    @State var page = Page.home
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("XemPhim").font(.system(size: 24, weight: .heavy)).foregroundColor(.accent)
                Spacer()
                Button { page = .search } label: { Image(systemName: "magnifyingglass").font(.title3).padding(10) }.foregroundColor(.white).accessibilityLabel("Tìm kiếm")
                Button { page = .account } label: { Image(systemName: "person.crop.circle").font(.title2).padding(8) }.foregroundColor(.white).accessibilityLabel("Tài khoản")
            }.padding(.horizontal, 20).padding(.top, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(Page.allCases, id: \.self) { p in Button { page = p } label: { Text(p.rawValue).font(.system(size: 14, weight: page == p ? .bold : .medium)).foregroundColor(page == p ? .white : .gray).padding(.vertical, 13).overlay(alignment: .bottom) { if page == p { Rectangle().fill(Color.accent).frame(height: 3) } } } }
                }.padding(.horizontal, 20)
            }
            Group {
                switch page {
                case .home: HomeScreen()
                case .search: SearchScreen()
                case .series: CatalogScreen(path: "series", title: "Series")
                case .movies: CatalogScreen(path: "movies", title: "Phim")
                case .lists: ListsScreen()
                case .account: AccountScreen()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(Color.navy)
    }
}

struct Poster: View {
    let media: Media
    var body: some View {
        NavigationLink { DetailsScreen(initial: media) } label: {
            VStack(alignment: .leading, spacing: 7) {
                Artwork(address: media.poster).frame(width: 112, height: 166).cornerRadius(8)
                Text(media.title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(2).frame(height: 34, alignment: .topLeading)
                HStack { Text(media.year); Spacer(); if media.rating > 0 { Text(String(format: "★ %.1f", media.rating)).foregroundColor(.yellow) } }.font(.caption2).foregroundColor(.secondary)
            }.frame(width: 112)
        }.buttonStyle(.plain)
    }
}
struct MediaRow: View {
    var title: String; var items: [Media]
    var ranges: [String: [Media]] = [:]
    @State var range = "day"
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.system(size: 20, weight: .bold)); Spacer()
                if !ranges.isEmpty {
                    Menu {
                        ForEach([("day", "Ngày"), ("week", "Tuần"), ("month", "Tháng")], id: \.0) { entry in if ranges[entry.0] != nil { Button(entry.1) { range = entry.0 } } }
                    } label: { Text(range == "day" ? "Ngày ▾" : range == "week" ? "Tuần ▾" : "Tháng ▾").font(.caption).foregroundColor(.white) }
                }
            }.padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) { LazyHStack(alignment: .top, spacing: 14) { ForEach(ranges[range] ?? items) { Poster(media: $0) } }.padding(.horizontal, 20) }
        }.padding(.vertical, 10)
    }
}
struct Hero: View {
    let media: Media
    @State var playback: PlayTarget?
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(address: media.backdrop.isEmpty ? media.poster : media.backdrop).frame(height: 330)
            LinearGradient(colors: [.navy.opacity(0.05), .navy.opacity(0.65), .navy], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text(media.title).font(.system(size: 29, weight: .heavy)).lineLimit(2)
                Text(media.summary).font(.caption).foregroundColor(.white.opacity(0.8))
                Text(Wire.clean(media.description)).font(.system(size: 13)).lineLimit(2).foregroundColor(.white.opacity(0.8))
                HStack {
                    Button { playback = PlayTarget(media: media) } label: { Label("Xem ngay", systemImage: "play.fill") }.buttonStyle(MainButton())
                    NavigationLink { DetailsScreen(initial: media) } label: { Text("Thông tin") }.buttonStyle(MainButton(secondary: true))
                }.padding(.top, 5)
            }.padding(20)
        }.frame(height: 330).clipped().fullScreenCover(item: $playback) { PlaybackScreen(target: $0) }
    }
}
struct HomeScreen: View {
    @EnvironmentObject var session: Session
    @State var categories: [Category] = []
    @State var error = ""
    @State var loading = true
    @State var refresh = 0
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if loading && categories.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(50) }
                if !error.isEmpty { Failure(message: error) { refresh += 1 } }
                if let first = categories.first?.items.first { Hero(media: first) }
                ForEach(Array(categories.enumerated()), id: \.offset) { _, row in if !row.items.isEmpty { MediaRow(title: row.title, items: row.items, ranges: row.ranges) } }
                if !loading && error.isEmpty && categories.isEmpty { Text("Chưa có phim trong danh mục.").padding(24) }
            }.padding(.bottom, 30)
        }.refreshable { await load() }.task(id: refresh) { await load() }
    }
    func load() async {
        loading = true; error = ""; defer { loading = false }
        do { let j = try await session.get("home"); categories = j.array.map(Category.init) }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct SearchScreen: View {
    @EnvironmentObject var session: Session
    @State var query = ""
    @State var items: [Media] = []
    @State var loading = false
    @State var error = ""
    var body: some View {
        VStack {
            HStack { Image(systemName: "magnifyingglass"); TextField("Tên phim, diễn viên…", text: $query).submitLabel(.search).disableAutocorrection(true); if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") } } }.padding(14).background(Color.raised).cornerRadius(8).padding(20)
            if loading { ProgressView() }
            if !error.isEmpty { Text(error).font(.footnote).padding(20) }
            ScrollView { MediaGrid(items: items).padding(.horizontal, 20); if !loading && !query.isEmpty && items.isEmpty && error.isEmpty { Text("Không có kết quả.").foregroundColor(.secondary).padding() } }
        }.task(id: query) {
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { items = []; error = ""; loading = false; return }
            loading = true; error = ""
            do { try await Task.sleep(nanoseconds: 400_000_000); let j = try await session.get("search", query: [URLQueryItem(name: "q", value: query)]); items = j.array.map(Media.init); loading = false }
            catch { if !Task.isCancelled { loading = false; self.error = error.localizedDescription } }
        }
    }
}
struct MediaGrid: View {
    let items: [Media]
    var body: some View { LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 14)], alignment: .leading, spacing: 22) { ForEach(items) { Poster(media: $0) } } }
}
struct CatalogScreen: View {
    @EnvironmentObject var session: Session
    var path, title: String
    @State var items: [Media] = []
    @State var filters: [JSON] = []
    @State var selected = -1
    @State var nextPage = 1
    @State var loading = false
    @State var error = ""
    @State var refresh = 0
    @State var loadID = UUID()
    var key: String { "\(path)-\(selected)-\(refresh)" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title).font(.title.bold())
                if !filters.isEmpty {
                    Menu {
                        Button("Tất cả") { selected = -1 }
                        ForEach(filters.indices, id: \.self) { i in Button(filters[i]["label"].string) { selected = i } }
                    } label: { Label(selected < 0 ? "Tất cả" : filters[selected]["label"].string, systemImage: "line.3.horizontal.decrease.circle") }.buttonStyle(MainButton(secondary: true))
                }
                if !error.isEmpty { Failure(message: error) { refresh += 1 } }
                MediaGrid(items: items)
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if !loading && nextPage > 0 { Button("Xem thêm") { Task { await load(reset: false) } }.buttonStyle(MainButton(secondary: true)) }
                if !loading && items.isEmpty && error.isEmpty { Text("Chưa có phim trong danh mục này.").foregroundColor(.secondary) }
            }.padding(20)
        }.id(path).task(id: key) { await load(reset: true) }
    }
    func load(reset: Bool) async {
        guard reset || !loading else { return }
        let token = UUID(); loadID = token; loading = true; error = ""
        defer { if token == loadID { loading = false } }
        if reset { items = []; nextPage = 1 }
        do {
            if filters.isEmpty && !path.hasPrefix("my-list/") {
                let freshFilters = try await session.get(path + "/filters").array
                guard token == loadID && !Task.isCancelled else { return }; filters = freshFilters
            }
            var q = [URLQueryItem(name: "page", value: String(nextPage))]
            if selected >= 0 && selected < filters.count {
                let f = filters[selected]
                for name in ["genre", "country"] where !f[name].isNull && !f[name].string.isEmpty { q.append(URLQueryItem(name: name, value: f[name].string)) }
                if f["short"].bool { q.append(URLQueryItem(name: "short", value: "true")) }
            }
            let j = try await session.get(path, query: q), fresh = j["items"].array.map(Media.init)
            guard token == loadID && !Task.isCancelled else { return }
            let existing = Set(items.map(\.id)); items += fresh.filter { !existing.contains($0.id) }
            nextPage = j["nextPage"].isNull ? 0 : Int(j["nextPage"].number)
        } catch { if !Task.isCancelled && token == loadID { self.error = error.localizedDescription } }
    }
}
struct ListsScreen: View {
    @State var tab = 0
    let rows = [("updates", "Có cập nhật mới"), ("watching", "Tiếp tục xem"), ("wishlist", "Mong muốn"), ("watched", "Xem lại")]
    var body: some View { VStack { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(rows.indices, id: \.self) { i in Button(rows[i].1) { tab = i }.buttonStyle(MainButton(secondary: tab != i)) } }.padding(20) }; CatalogScreen(path: "my-list/" + rows[tab].0, title: rows[tab].1).id(tab) } }
}

struct DetailsScreen: View {
    @EnvironmentObject var session: Session
    let initial: Media
    @State var media: Media?
    @State var seasons: [Season] = []
    @State var episodes: [Episode] = []
    @State var seasonID = ""
    @State var status = ""
    @State var error = ""
    @State var loading = true
    @State var playback: PlayTarget?
    @State var rental: RentalTarget?
    var current: Media { media ?? initial }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Artwork(address: current.backdrop.isEmpty ? current.poster : current.backdrop).frame(height: 210).cornerRadius(10)
                HStack(alignment: .top, spacing: 18) {
                    Artwork(address: current.poster).frame(width: 100, height: 150).cornerRadius(8)
                    VStack(alignment: .leading, spacing: 10) { Text(current.title).font(.title2.bold()); Text(current.summary).font(.caption).foregroundColor(.secondary); if current.rating > 0 { Text(String(format: "★ %.1f", current.rating)).foregroundColor(.yellow) }; Text(current.genres.joined(separator: " · ")).font(.caption) }
                }
                HStack {
                    Button { playback = PlayTarget(media: current) } label: { Label("Xem phim", systemImage: "play.fill") }.buttonStyle(MainButton())
                    Menu {
                        ForEach([("watching", "Đang xem"), ("wishlist", "Mong muốn"), ("watched", "Đã xem")], id: \.0) { value in Button(value.1) { Task { await setList(value.0) } } }
                        Button("Xóa khỏi danh sách", role: .destructive) { Task { await setList(nil) } }
                    } label: { Label(status.isEmpty ? "Danh sách" : "Đã lưu", systemImage: status.isEmpty ? "plus" : "checkmark") }.buttonStyle(MainButton(secondary: true))
                }
                if !current.isSeries {
                    Button { rental = RentalTarget(id: current.id, title: current.title) } label: { Label("Thuê lẻ phim này", systemImage: "cart") }.buttonStyle(MainButton(secondary: true))
                } else { Text("Chọn Thuê tập bên cạnh tập muốn xem.").font(.caption).foregroundColor(.secondary) }
                Text(Wire.clean(current.description)).font(.system(size: 15)).foregroundColor(.white.opacity(0.8)).textSelection(.enabled)
                if !current.actors.isEmpty { Text("Diễn viên: " + current.actors.joined(separator: ", ")).font(.footnote).foregroundColor(.secondary) }
                if !current.countries.isEmpty { Text(current.countries.joined(separator: " · ")).font(.footnote).foregroundColor(.secondary) }
                if !seasons.isEmpty {
                    Picker("Mùa", selection: $seasonID) { ForEach(seasons) { s in Text("Mùa \(s.number) · \(s.count) tập").tag(s.id) } }.pickerStyle(.menu)
                    ForEach(episodes) { ep in HStack {
                        Button { playback = PlayTarget(id: ep.id, title: current.title + " · Tập \(ep.number)", resolveSeries: false) } label: { HStack { Image(systemName: "play.circle.fill"); VStack(alignment: .leading) { Text("Tập \(ep.number): \(ep.name)").font(.system(size: 15, weight: .medium)); if !ep.duration.isEmpty { Text(ep.duration).font(.caption).foregroundColor(.secondary) } }; Spacer() }.padding(16).background(Color.surface).cornerRadius(8) }.foregroundColor(.white)
                        Button("Thuê tập") { rental = RentalTarget(id: ep.id, title: current.title + " · Tập \(ep.number)") }.buttonStyle(MainButton(secondary: true))
                    } }
                }
                if loading { ProgressView() }
                if !error.isEmpty { Text(error).font(.footnote).foregroundColor(.orange); Button("Thử tải lại") { Task { await load() } }.buttonStyle(MainButton(secondary: true)) }
            }.padding(20)
        }.background(Color.navy).navigationBarHidden(false).navigationTitle(current.title).navigationBarTitleDisplayMode(.inline)
            .task { await load() }.task(id: seasonID) {
                guard !seasonID.isEmpty else { return }; episodes = []
                do { episodes = try await session.get("seasons/" + Wire.segment(seasonID) + "/episodes").array.map(Episode.init) } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }.fullScreenCover(item: $playback) { PlaybackScreen(target: $0) }
            .sheet(item: $rental) { item in RentalSheet(target: item) { source in rental = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { playback = source } } }
    }
    func load() async {
        loading = true; error = ""; defer { loading = false }
        do {
            let root = "titles/" + Wire.segment(initial.id); media = Media(try await session.get(root))
            if current.isSeries { seasons = try await session.get(root + "/seasons").array.map(Season.init); if seasonID.isEmpty { seasonID = seasons.first?.id ?? "" } }
            let list = try await session.get(root + "/my-list"); status = list["status"].string
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func setList(_ value: String?) async {
        do { _ = try await session.get("titles/" + Wire.segment(current.id) + "/my-list", method: value == nil ? "DELETE" : "PUT", body: value.map { ["status": $0] }); status = value ?? "" } catch { session.report(error) }
    }
}
struct AccountScreen: View {
    @EnvironmentObject var session: Session
    @State var account = JSON()
    @State var vip = JSON()
    @State var error = ""
    @State var loading = true
    @State var confirmLogout = false
    @State var web = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 22) {
            Text("Tài khoản").font(.title.bold())
            Label(session.login?.name ?? "", systemImage: "person.crop.circle.fill").font(.title2)
            Text(session.login?.email ?? "").foregroundColor(.secondary)
            if loading { ProgressView() }
            if !error.isEmpty { Failure(message: error) { Task { await load() } } }
            if !loading && error.isEmpty {
                VStack(alignment: .leading, spacing: 16) { Text("Số dư: \(Int(account["balance"].number))"); Text(vip["active"].bool ? "VIP đang hoạt động" : "Chưa có VIP đang hoạt động"); Text(vip["expiresAt"].string.isEmpty ? account["vipExpiresAt"].string : vip["expiresAt"].string).font(.footnote).foregroundColor(.secondary) }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.surface).cornerRadius(10)
            }
            Button("Mở Phimbar · Quản lý tài khoản") { web = true }.buttonStyle(MainButton(secondary: true))
            Button("Đăng xuất") { confirmLogout = true }.buttonStyle(MainButton())
            Text("XemPhim cho iOS · 1.1.1\nAPI phimfly.com · Tương thích iOS 15 trở lên").font(.caption).foregroundColor(.secondary)
        }.padding(24) }.task { await load() }.sheet(isPresented: $web) { SafariPage(url: URL(string: "https://phimbar.com/")!) }
            .confirmationDialog("Đăng xuất khỏi XemPhim?", isPresented: $confirmLogout) { Button("Đăng xuất", role: .destructive) { Task { do { try await session.logout() } catch { session.report(error) } } } }
    }
    func load() async { loading = true; error = ""; defer { loading = false }; do { account = try await session.get("account"); vip = try await session.get("vip") } catch { if !Task.isCancelled { self.error = error.localizedDescription } } }
}
