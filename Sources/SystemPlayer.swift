import SwiftUI
import AVKit
import Combine

// Present AVPlayerViewController itself, rather than embedding it below custom
// transport controls. Both screens retain the same AVPlayer and current item.
@MainActor struct SystemPlayerPresenter: UIViewControllerRepresentable {
    @ObservedObject var playback: Playback
    @Binding var isPresented: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> Anchor {
        let anchor = Anchor(); anchor.view.backgroundColor = .clear
        anchor.returned = { [weak coordinator = context.coordinator] in coordinator?.returned() }
        return anchor
    }
    func updateUIViewController(_ anchor: Anchor, context: Context) {
        context.coordinator.parent = self
        guard isPresented, !playback.loading, playback.player.currentItem != nil, anchor.view.window != nil else { return }
        context.coordinator.open(from: anchor)
    }
    final class Anchor: UIViewController {
        var returned: (() -> Void)?
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); returned?() }
    }
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
        var parent: SystemPlayerPresenter
        private var controller: AVPlayerViewController?
        private var captions: UIHostingController<SystemCaptions>?
        private var closing = false
        init(_ parent: SystemPlayerPresenter) { self.parent = parent }
        func open(from anchor: Anchor) {
            guard controller == nil, anchor.presentedViewController == nil else { return }
            let vc = AVPlayerViewController(); controller = vc; closing = false
            vc.player = parent.playback.player; vc.showsPlaybackControls = true
            vc.allowsPictureInPicturePlayback = true; vc.modalPresentationStyle = .fullScreen
            vc.delegate = self; vc.loadViewIfNeeded()
            if let overlay = vc.contentOverlayView {
                let host = UIHostingController(rootView: SystemCaptions(playback: parent.playback))
                captions = host; host.view.backgroundColor = .clear; host.view.isUserInteractionEnabled = false
                vc.addChild(host); overlay.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo: overlay.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: overlay.trailingAnchor), host.view.topAnchor.constraint(equalTo: overlay.topAnchor), host.view.bottomAnchor.constraint(equalTo: overlay.bottomAnchor)])
                host.didMove(toParent: vc)
            }
            anchor.present(vc, animated: true) { [weak self] in
                vc.presentationController?.delegate = self
                #if UI_PREVIEW
                self?.verifyPreview(vc)
                #endif
            }
        }
        func returned() { if let vc = controller, vc.presentingViewController == nil { finish() } }
        func finish() {
            guard controller != nil, !closing else { return }; closing = true
            controller?.player = nil; controller = nil; captions = nil
            parent.playback.restoreInlineVideo()
            parent.isPresented = false
            Task { await parent.playback.saveProgress() }
        }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish() }
        func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.finish() }
        }
        #if UI_PREVIEW
        private func verifyPreview(_ vc: AVPlayerViewController) {
            guard CommandLine.arguments.contains("--fixture-fullscreen"), !CommandLine.arguments.contains("--ui-controls") else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let player = parent.playback.player, item = player.currentItem
                player.pause(); let paused = player.rate == 0
                let sought = await withCheckedContinuation { continuation in player.seek(to: CMTime(seconds: 75, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { continuation.resume(returning: $0) } }
                let position = player.currentTime().seconds
                player.play()
                var record: [String: Any] = ["nativeController": vc.presentingViewController != nil, "nativeControls": vc.showsPlaybackControls, "samePlayer": vc.player === player, "pauseWorked": paused, "seekWorked": sought && abs(position - 75) < 1, "positionAfterSeek": position, "duration": item?.duration.seconds ?? 0]
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("native-fullscreen-verification.json")
                try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: url)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                vc.showsPlaybackControls = false; vc.showsPlaybackControls = true
                try? await Task.sleep(nanoseconds: 19_000_000_000)
                vc.dismiss(animated: true) { [weak self] in
                    self?.finish()
                    record["returnedToPlayer"] = player.currentItem === item && player.currentItem != nil
                    record["positionAfterReturn"] = player.currentTime().seconds
                    try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: url)
                }
            }
        }
        #endif
    }
}

private struct SystemCaptions: View {
    @ObservedObject var playback: Playback
    @AppStorage("subtitle.size") var size = 22.0
    @AppStorage("subtitle.bottom") var bottom = 50.0
    @AppStorage("subtitle.background") var background = true
    @AppStorage("subtitle.yellow") var yellow = false
    var body: some View {
        VStack { Spacer(); if !playback.caption.isEmpty {
            Text(playback.caption).font(.system(size: size, weight: .semibold)).foregroundColor(yellow ? .yellow : .white)
                .multilineTextAlignment(.center).padding(8).background(background ? Color.black.opacity(0.65) : Color.clear).cornerRadius(4)
                .shadow(color: .black, radius: 2).padding(.horizontal, 24).padding(.bottom, bottom)
        } }.frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
    }
}
