import SwiftUI
import WebKit

struct RentalTarget: Identifiable { let id, title: String }
struct WebSubtitle { let label, language: String; let cues: [Cue] }
struct WebPlayback {
    let url: URL, page: URL
    let time: Double
    let cookies: [HTTPCookie]
    let subtitles: [WebSubtitle]
    let userAgent: String
}
enum RentalPolicy {
    static func watchURL(_ id: String) -> URL? {
        guard !id.isEmpty else { return nil }
        return URL(string: "https://phimbar.com/watch/" + Wire.segment(id))
    }
    static func trusted(_ url: URL?) -> Bool {
        guard let url = url, url.scheme == "https", url.user == nil, url.password == nil else { return false }
        return ["phimbar.com", "phimfly.com"].contains(url.host?.lowercased() ?? "")
    }
    static func watchID(_ url: URL?) -> String? {
        guard trusted(url), let url = url else { return nil }; let parts = url.path.split(separator: "/")
        return parts.count == 2 && parts[0] == "watch" ? String(parts[1]) : nil
    }
}
@MainActor final class RentalController: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    @Published var note = "Đăng nhập Phimbar trong khung này nếu được yêu cầu, rồi chọn thuê đúng tập."
    @Published var offer: JSON?
    let target: RentalTarget
    var web: WKWebView!
    var completed: ((PlayTarget) -> Void)?
    private var confirming = false
    init(target: RentalTarget) {
        self.target = target; super.init()
        let config = WKWebViewConfiguration(); config.websiteDataStore = .default(); config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.userContentController.add(self, name: "rental")
        let bundle = Bundle.main
        let css = (try? String(contentsOf: bundle.url(forResource: "legacy", withExtension: "css")!, encoding: .utf8)) ?? ""
        let cssJSON = String(data: try! JSONSerialization.data(withJSONObject: [css]), encoding: .utf8)!
        let compat = (try? String(contentsOf: bundle.url(forResource: "compat", withExtension: "js")!, encoding: .utf8)) ?? ""
        let script = (try? String(contentsOf: bundle.url(forResource: "rental", withExtension: "js")!, encoding: .utf8)) ?? ""
        config.userContentController.addUserScript(WKUserScript(source: "window.__phimbarLegacyCSS=" + cssJSON + "[0];\n" + compat, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        web = WKWebView(frame: .zero, configuration: config); web.navigationDelegate = self; web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true; web.isOpaque = false; web.backgroundColor = UIColor(Color.navy)
        if let url = RentalPolicy.watchURL(target.id) { web.load(URLRequest(url: url)) }
    }
    func close() { web.stopLoading(); web.configuration.userContentController.removeScriptMessageHandler(forName: "rental"); completed = nil }
    func prepare() {
        guard RentalPolicy.watchID(web.url) != nil else { note = "Hãy đăng nhập trước. App sẽ trở về phim/tập bạn chọn."; return }
        web.evaluateJavaScript("window.XemRental ? window.XemRental.prepare() : 'waiting'") { [weak self] value, error in
            self?.note = value as? String == "open" ? "Chỉ chọn Thuê lẻ cho phim/tập này. Giá hiển thị do Phimbar cung cấp." : "Trang đang tải hoặc tập đã có quyền VIP. Bạn có thể chọn Phát tập đã thuê khi website đã có video."
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, ["phimbar.com", "phimfly.com"].contains(message.frameInfo.securityOrigin.host.lowercased()),
              RentalPolicy.watchID(web.url) == target.id, !confirming, let value = message.body as? [String: Any] else { return }
        let j = JSON(value); guard j["page"].string == web.url?.absoluteString, !j["fingerprint"].string.isEmpty, !j["price"].string.isEmpty else { return }
        confirming = true; offer = j
    }
    func cancelOffer() { confirming = false; offer = nil }
    func confirmOffer(_ value: JSON) {
        let fingerprint = value["fingerprint"].string
        cancelOffer()
        let literal = String(data: try! JSONSerialization.data(withJSONObject: [fingerprint]), encoding: .utf8)!
        web.evaluateJavaScript("window.XemRental && window.XemRental.commit(" + literal + "[0])") { [weak self] result, _ in
            self?.note = (result as? Bool == true) ? "Phimbar đang xử lý thuê lẻ. Không bấm mua lại. Khi website cho phát, chọn Phát tập đã thuê." : "Giá hoặc tập đã thay đổi. Mở lại Thuê tập này và kiểm tra trước khi xác nhận."
        }
    }
    func play() {
        guard let page = web.url, let id = RentalPolicy.watchID(page), id == target.id else { note = "Hãy đăng nhập và mở đúng phim/tập đã chọn. Đóng màn này rồi chọn Thuê tập ở đúng tập nếu muốn đổi."; return }
        web.evaluateJavaScript("window.XemRental && window.XemRental.snapshot()") { [weak self] value, _ in
            guard let self = self else { return }; let j = JSON(value ?? NSNull())
            guard j["page"].string == page.absoluteString, let url = j["urls"].array.compactMap({ Wire.safeURL($0.string) }).first else {
                self.note = "Website chưa cấp nguồn phát. Hoàn tất thuê lẻ và bấm phát trên website trước, rồi chọn nút này."; return
            }
            let subs = j["subtitles"].array.map { sub in WebSubtitle(label: sub["label"].string, language: sub["language"].string, cues: sub["cues"].array.compactMap { c in
                let start = c["start"].number, end = c["end"].number
                return start.isFinite && end.isFinite && end > start ? Cue(start: start, end: end, text: Wire.clean(c["text"].string)) : nil
            }) }
            self.web.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                Task { @MainActor in
                    let source = WebPlayback(url: url, page: page, time: max(0, j["time"].number), cookies: cookies, subtitles: subs, userAgent: j["ua"].string)
                    self.completed?(PlayTarget(id: id, title: self.target.title, resolveSeries: false, web: source))
                }
            }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { note = RentalPolicy.watchID(webView.url) != nil ? "Chọn Thuê tập này để xem giá thuê lẻ của đúng phim/tập." : "Đăng nhập website bằng tài khoản của bạn; không cần gửi mật khẩu vào chat." }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        guard RentalPolicy.trusted(action.request.url) else { decisionHandler(.cancel); note = "Trang ngoài dịch vụ đã được chặn trong màn thuê lẻ."; return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil && RentalPolicy.trusted(action.request.url) { webView.load(action.request) }; return nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { note = "Không tải được website. Kiểm tra mạng và bấm tải lại." } }
}
struct RentalWeb: UIViewRepresentable {
    let controller: RentalController
    func makeUIView(context: Context) -> WKWebView { controller.web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
@MainActor struct RentalSheet: View {
    @StateObject var controller: RentalController
    @Environment(\.dismiss) var dismiss
    let onPlay: (PlayTarget) -> Void
    init(target: RentalTarget, onPlay: @escaping (PlayTarget) -> Void) { _controller = StateObject(wrappedValue: RentalController(target: target)); self.onPlay = onPlay }
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Text(controller.note).font(.caption).foregroundColor(.secondary).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                RentalWeb(controller: controller)
                ScrollView(.horizontal, showsIndicators: false) { HStack {
                    Button("Thuê tập này") { controller.prepare() }.buttonStyle(MainButton(secondary: true))
                    Button("▶ Phát tập đã thuê") { controller.play() }.buttonStyle(MainButton())
                }.padding(12) }
            }.background(Color.navy).navigationTitle("Thuê lẻ · " + controller.target.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }; ToolbarItem(placement: .navigationBarTrailing) { Button { controller.web.reload() } label: { Image(systemName: "arrow.clockwise") } } }
                .alert("Xác nhận thuê lẻ", isPresented: Binding(get: { controller.offer != nil }, set: { if !$0 { controller.cancelOffer() } }), presenting: controller.offer) { value in
                    Button("Hủy", role: .cancel) { controller.cancelOffer() }
                    Button("Xác nhận thuê") { controller.confirmOffer(value) }
                } message: { value in Text(value["title"].string + "\nGiá: " + value["price"].string + "\n" + value["term"].string + "\nThanh toán bằng tài khoản đang đăng nhập trên website.") }
        }.navigationViewStyle(.stack).preferredColorScheme(.dark)
            .onAppear { controller.completed = { target in dismiss(); onPlay(target) } }.onDisappear { controller.close() }
    }
}
