import XCTest

/// **The Home Screen by stage, and each film's own bar** (his asks,
/// 2026-10-11). Needs the local records server the check script starts
/// (`-PortalURL http://127.0.0.1:8899`), on the simulator's own copies of
/// CHB, LC and T.
final class HomeAndBar: XCTestCase {

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

    private func home(_ app: XCUIApplication) {
        if app.buttons["film.menu"].waitForExistence(timeout: 8) {
            app.buttons["film.menu"].tap()
            app.buttons["film.allprojects"].tap()
        }
        XCTAssertTrue(app.buttons["phone.settings"].waitForExistence(timeout: 10), "no Home Screen")
    }

    private func open(_ app: XCUIApplication, _ film: String) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", film)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(film) is not on the Home Screen")
        row.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15), "\(film) did not open")
    }

    func testHomeIsGroupedByStageAndEachFilmKeepsItsBar() {
        let app = XCUIApplication()
        app.launchArguments = ["-PortalURL", "http://127.0.0.1:8899", "-PortalToken", "test"]
        app.launch()
        home(app)

        for stage in ["Active", "Development", "Post"] {
            XCTAssertTrue(app.staticTexts[stage].waitForExistence(timeout: 10), "no \(stage) group")
        }
        photo("home-1-grouped")

        // CHB: put Diagrams where Shot List was.
        open(app, "CHB")
        app.tabBars.buttons["Library"].tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit"].waitForExistence(timeout: 5), "Edit did not open")
        let slot = app.scrollViews.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Shot")).firstMatch
        if !slot.waitForExistence(timeout: 5) { print(app.debugDescription) }
        XCTAssertTrue(slot.exists, "no first slot")
        slot.tap()
        // The menu's own entry (the Library row behind the sheet shares its name).
        let choice = app.buttons.matching(identifier: "pencil.and.ruler").firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "the slot's menu does not offer Diagrams")
        choice.tap()
        photo("bar-1-edited")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Diagrams"].waitForExistence(timeout: 5), "CHB's bar did not take Diagrams")

        // LC: its bar is as it was.
        app.tabBars.buttons["Library"].tap()
        home(app)
        open(app, "LC")
        photo("bar-2-other-film")
        XCTAssertFalse(app.tabBars.buttons["Diagrams"].exists, "LC's bar followed CHB's edit")

        // And CHB still has it.
        app.buttons["film.menu"].tap()
        app.buttons["film.allprojects"].tap()
        open(app, "CHB")
        XCTAssertTrue(app.tabBars.buttons["Diagrams"].waitForExistence(timeout: 5), "CHB lost its own bar")
        // A film that has moved Shot List off its bar opens on its first pin.
        XCTAssertTrue(app.tabBars.buttons["Diagrams"].isSelected, "CHB did not open on its first pin")
    }
}
