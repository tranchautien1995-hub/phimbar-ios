import XCTest

final class NativeControlsTests: XCTestCase {
    func testNativePauseScrubAndClose() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "vn.onnstream.phimbar.ios")
        app.launchArguments = ["--fixture-fullscreen", "--ui-controls"]
        app.launch()
        let pause = app.buttons.matching(NSPredicate(format: "label ==[c] 'Pause'")).firstMatch
        if !pause.waitForExistence(timeout: 15) { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap() }
        XCTAssertTrue(pause.waitForExistence(timeout: 10), app.debugDescription)
        if !pause.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap() }
        snapshot("native-controls")
        pause.tap()
        let play = app.buttons.matching(NSPredicate(format: "label ==[c] 'Play'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 5), app.debugDescription)
        snapshot("native-paused")
        let slider = app.sliders.allElementsBoundByIndex.first(where: { $0.isHittable })
        XCTAssertNotNil(slider, app.debugDescription)
        slider?.adjust(toNormalizedSliderPosition: 0.3)
        snapshot("native-scrubbed")
        play.tap()
        let close = app.buttons.matching(NSPredicate(format: "label ==[c] 'Close' OR label ==[c] 'Done'")).firstMatch
        if !close.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap() }
        XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
        close.tap()
        XCTAssertTrue(app.buttons["Toàn màn hình iOS"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Phim kiểm tra"].exists, app.debugDescription)
        snapshot("returned-to-app-player")
    }
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
