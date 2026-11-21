import XCTest

final class NativeControlsTests: XCTestCase {
    func testNativePauseResumeAndClose() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "vn.onnstream.phimbar.ios")
        app.launchArguments = ["--fixture-fullscreen", "--ui-controls"]
        app.launch()
        XCTAssertTrue(app.otherElements["Video"].waitForExistence(timeout: 30), app.debugDescription)
        let transport = app.buttons.matching(identifier: "Play/Pause").firstMatch
        tap(transport, in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label ==[c] 'Pause'")).firstMatch.waitForExistence(timeout: 3), app.debugDescription)
        tap(transport, in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label ==[c] 'Play'")).firstMatch.waitForExistence(timeout: 3), app.debugDescription)
        snapshot("native-paused")
        let close = app.buttons.matching(NSPredicate(format: "label ==[c] 'Close' OR label ==[c] 'Done'")).firstMatch
        tap(close, in: app)
        XCTAssertTrue(app.buttons.matching(identifier: "Toàn màn hình iOS").firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Phim kiểm tra"].exists, app.debugDescription)
        snapshot("returned-to-app-player")
    }
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.exists {
                let frame = element.frame
                if element.isHittable && frame.width > 0 {
                    app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
                    return
                }
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        }
        XCTFail("Native button not hittable: " + app.debugDescription)
    }
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
