import XCTest

/// **A photograph of a list mid-scroll.** A pinned header only misbehaves
/// once something has gone behind it, and no screenshot taken from outside
/// can catch that moment, so the test takes it from inside and writes it
/// where a person can look: /tmp/shotlist-scrolled.png.
final class Hold: XCTestCase {
    func testScrollAndPhotograph() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--film", "CHB", "0"]
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
        for _ in 0..<3 { app.scrollViews.firstMatch.swipeUp(velocity: .slow) }
        Thread.sleep(forTimeInterval: 2)
        let shot = XCUIScreen.main.screenshot()
        try shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/shotlist-scrolled.png"))
    }
}
