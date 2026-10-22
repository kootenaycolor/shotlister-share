import XCTest

/// **Shortcuts actions** (2026-10-09): photos handed over by *Upload Photos*
/// ask where they go and land there. Adds two made-up photos to a test project's Mansion in the simulator's own copy.
final class Shortcuts: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func photo(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let keep = XCTAttachment(screenshot: shot)
        keep.name = name
        keep.lifetime = .keepAlways
        add(keep)
        if let out = ProcessInfo.processInfo.environment["SHOTS_OUT"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
        }
    }

    func testUploadPhotosAsksWhereAndLands() {
        let app = XCUIApplication()
        app.launchArguments = ["--intent", "photos", "CHB"]
        app.launch()

        let mansion = app.buttons["drop.location.Mansion"]
        XCTAssertTrue(mansion.waitForExistence(timeout: 25), "no Add Photos sheet with Mansion")
        XCTAssertTrue(app.navigationBars["Add 2 Photos"].exists, "the sheet does not count two photos")
        photo("shortcuts-1-drop")
        mansion.tap()

        sleep(3)
        photo("shortcuts-2-landed")
        XCTAssertTrue(app.navigationBars["Locations"].waitForExistence(timeout: 10), "did not go to Locations")
    }
}
