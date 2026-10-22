import XCTest

/// **Details, in sight and staying up** (his note, 2026-10-17): a picked
/// piece's bar shows Details first; the sheet rises half height with the plan
/// still live above it, follows the next piece tapped, lowers when nothing is
/// picked and comes back with the next pick until Done. Needs a film "Daybreak"
/// in the simulator's Documents whose scene 34 has two lamps (TAP_A / TAP_B:
/// "x,y" in points, where they stand on the plan).
final class DiagramDetails: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func photo(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let keep = XCTAttachment(screenshot: shot)
        keep.name = name
        keep.lifetime = .keepAlways
        add(keep)
        if let out = ProcessInfo.processInfo.environment["SHOTS_OUT"] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_SHOTS_OUT"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
        }
    }

    private func point(_ key: String, _ fallback: CGVector, in app: XCUIApplication) -> XCUICoordinate {
        let env = ProcessInfo.processInfo.environment
        let raw = env[key] ?? env["TEST_RUNNER_" + key]
        let parts = raw?.split(separator: ",").compactMap { Double($0) } ?? []
        let origin = app.coordinate(withNormalizedOffset: .zero)
        if parts.count == 2 { return origin.withOffset(CGVector(dx: parts[0], dy: parts[1])) }
        return origin.withOffset(fallback)
    }

    func testDetailsIsInSightAndStaysUp() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["TAP_A"] ?? env["TEST_RUNNER_TAP_A"] != nil else {
            throw XCTSkip("needs the seeded Daybreak film and TAP_A / TAP_B")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--film", "Daybreak", "6"]
        app.launch()
        let scene = app.buttons.containing(NSPredicate(format: "label CONTAINS 'INT. CAR'")).firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 20), "no scene row")
        scene.tap()
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10), "no Edit")
        edit.tap()
        sleep(2)
        photo("dd-0-plan")
        point("TAP_A", CGVector(dx: 140, dy: 380), in: app).tap()
        sleep(1)
        photo("dd-1-picked")
        let details = app.buttons["diagram.details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5), "no Details button in the piece's bar")
        details.tap()
        sleep(2)
        photo("dd-2-sheet")
        // The sheet's own bar, titled by the piece (the editor's has Done too).
        let sheet = app.navigationBars["Light"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "the sheet did not rise")
        // The plan stays live above it: the other lamp, tapped, is shown.
        point("TAP_B", CGVector(dx: 230, dy: 300), in: app).tap()
        sleep(2)
        photo("dd-3-other")
        XCTAssertTrue(sheet.exists, "the sheet went away on the next pick")
        sheet.buttons["Done"].tap()
        sleep(2)
        photo("dd-4-done")
        XCTAssertFalse(app.navigationBars["Light"].exists, "Done did not shut it")
        // Shut, it stays shut on the next pick.
        point("TAP_A", CGVector(dx: 140, dy: 380), in: app).tap()
        sleep(2)
        XCTAssertFalse(app.navigationBars["Light"].exists, "it came back by itself")
    }
}
