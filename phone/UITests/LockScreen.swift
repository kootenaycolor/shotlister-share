import XCTest

/// **Lock screen shortcuts** (his ask, 2026-10-09): set in Settings, a film
/// and a page, and the address a widget opens lands on that page, pinned or
/// not. Works on the simulator's own copy of Call Her Back.
final class LockScreen: XCTestCase {

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

    func testShortcutIsSetInSettingsAndOpensItsPage() {
        let app = XCUIApplication()
        app.launch()

        // The last film reopens at launch; Settings is on the Projects list.
        let gear = app.buttons["phone.settings"]
        if app.buttons["film.menu"].waitForExistence(timeout: 10) {
            app.buttons["film.menu"].tap()
            app.buttons["film.allprojects"].tap()
        }
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "no Settings on Projects")
        // A film closing swallows a tap; press until the sheet is up.
        for _ in 0..<4 where !app.navigationBars["Settings"].exists {
            sleep(1)
            gear.tap()
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings did not open")
        photo("lock-0-settings")
        app.buttons["settings.lockscreen"].tap()

        let one = app.descendants(matching: .any)["lock.shortcut.1"].firstMatch
        if !one.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(one.waitForExistence(timeout: 5), "no Lock Screen shortcuts in Settings")
        photo("lock-1-settings")
        one.tap()

        app.descendants(matching: .any)["lock.film"].firstMatch.tap()
        let chb = app.buttons["CHB"]
        XCTAssertTrue(chb.waitForExistence(timeout: 5), "CHB is not offered")
        chb.tap()
        let page = app.descendants(matching: .any)["lock.page"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5), "no Page once a film is chosen")
        page.tap()
        let diagrams = app.buttons["Diagrams"]
        XCTAssertTrue(diagrams.waitForExistence(timeout: 5), "Diagrams is not offered")
        diagrams.tap()
        sleep(1)
        photo("lock-2-editor")

        app.navigationBars["Shortcut 1"].buttons.firstMatch.tap()
        XCTAssertTrue(one.waitForExistence(timeout: 5))
        XCTAssertTrue(one.label.contains("CHB · Diagrams"), "the row reads \(one.label)")
        photo("lock-3-saved")

        // What the widget opens. Diagrams is not pinned, so it opens inside
        // the Library, one step in.
        app.open(URL(string: "shotlister://film?film=CHB&place=diagrams")!)
        let library = app.tabBars.buttons["Library"]
        let opened = library.waitForExistence(timeout: 20)
        sleep(2)
        photo("lock-4-opened")
        XCTAssertTrue(opened, "the film did not open")
        XCTAssertTrue(library.isSelected, "Library is not chosen")
        XCTAssertTrue(app.navigationBars["Diagrams"].exists || app.staticTexts["Scenes"].exists,
                      "Diagrams is not on screen")

        // And a pinned page, with the film already open.
        app.open(URL(string: "shotlister://film?film=CHB&place=schedule")!)
        let schedule = app.tabBars.buttons["Schedule"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 10))
        sleep(1)
        XCTAssertTrue(schedule.isSelected, "an open film did not move to Schedule")
        photo("lock-5-schedule")
    }

    /// App Settings, from inside a film: the film's name, then App Settings,
    /// holds the Lock Screen shortcuts too (his ask, 2026-10-09).
    func testAppSettingsOpenFromTheFilmsName() {
        let app = XCUIApplication()
        app.launchArguments = ["--film", "CHB", "0"]
        app.launch()

        let film = app.buttons["film.menu"]
        XCTAssertTrue(film.waitForExistence(timeout: 20), "no film menu")
        film.tap()
        let settings = app.buttons["film.settings"]
        if !settings.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "no Project Settings in the film's menu")
        photo("lock-6-filmmenu")
        settings.tap()
        // It opens on the project's page; Back is the rest of Settings.
        let back = app.navigationBars.buttons["Settings"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Settings did not open on the project's page")
        photo("lock-6b-projectpage")
        back.tap()
        XCTAssertTrue(app.buttons["settings.project"].waitForExistence(timeout: 5), "Settings has no project row")
        photo("lock-6c-settingsroot")
        let lock = app.buttons["settings.lockscreen"]
        XCTAssertTrue(lock.waitForExistence(timeout: 5), "Settings has no Lock Screen row")
        lock.tap()
        let one = app.descendants(matching: .any)["lock.shortcut.1"].firstMatch
        for _ in 0..<3 where !one.exists { app.swipeUp() }
        XCTAssertTrue(one.waitForExistence(timeout: 5), "Settings has no Lock Screen shortcuts")
        photo("lock-7-appsettings")
    }
}
