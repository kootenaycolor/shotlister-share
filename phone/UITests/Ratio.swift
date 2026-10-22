import XCTest

/// **The iPhone offers the Mac's frames** (2026-10-09): Film Settings'
/// Aspect Ratio is the shared `Ratios` list, groups and Custom… included, and
/// a ratio not on the old eight (9:16) is taken and shown as itself. Puts the
/// film's own ratio back after.
final class Ratio: XCTestCase {

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

    func testRatioMenuOffersTheMacsFrames() {
        let app = XCUIApplication()
        app.launchArguments = ["--film", "CHB", "0"]
        app.launch()

        let film = app.buttons["film.menu"]
        XCTAssertTrue(film.waitForExistence(timeout: 20), "no film menu")
        film.tap()
        let settings = app.buttons["film.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "no Film Settings")
        settings.tap()

        let menu = app.buttons["ratio-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "no Aspect Ratio menu")
        // The row reads "Aspect Ratio, 4:3"; the menu's own rows say "4:3".
        let was = String(menu.label.split(separator: ",").last ?? "").trimmingCharacters(in: .whitespaces)
        menu.tap()
        sleep(1)
        photo("ratio-1-menu")
        if let out = ProcessInfo.processInfo.environment["SHOTS_OUT"] {
            try? app.debugDescription.write(toFile: out + "/tree.txt", atomically: true, encoding: .utf8)
        }
        for name in ["2.76:1 · Ultra Panavision 70", "2.35:1", "1.90:1 · IMAX Digital",
                     "1.43:1 · IMAX", "4:5 · Portrait", "9:16 · Vertical", "Custom…"] {
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 3), "the menu has no \(name)")
        }
        app.buttons["9:16 · Vertical"].tap()
        sleep(1)
        XCTAssertTrue(menu.label.contains("9:16"), "picking 9:16 shows \(menu.label)")
        photo("ratio-2-vertical")

        // Custom…: typed the way he would say it.
        menu.tap()
        app.buttons["Custom…"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Custom… asked for nothing")
        field.typeText("2.55:1")
        photo("ratio-3-custom")
        app.buttons["Set"].tap()
        sleep(1)
        XCTAssertTrue(menu.label.contains("2.55"), "a custom 2.55 shows \(menu.label)")

        // Back to what the film had.
        menu.tap()
        let back = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", was)).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 3), "the menu lost the film's own \(was)")
        back.tap()
        sleep(1)
        XCTAssertTrue(menu.label.hasSuffix(was), "the film's ratio did not come back: \(menu.label)")
    }
}

/// **The rest of the 2026-10-09 parity pass**: the Mac's ready-made columns,
/// a day's order from its menu, and a scene's Inside / Outside taking any
/// word. Each puts the film back the way it found it.
final class Parity: XCTestCase {

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

    private func open() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--film", "CHB", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["film.menu"].waitForExistence(timeout: 20), "no film menu")
        return app
    }

    func testReadyMadeColumn() {
        let app = open()
        app.buttons["film.menu"].tap()
        app.buttons["film.settings"].tap()
        let edit = app.buttons["Edit Columns"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        // A run that died before tidying leaves the column behind: delete it
        // first (it sits with the columns, above the ready-made ones).
        let row = app.switches.matching(NSPredicate(format: "label CONTAINS 'Frame Rate'")).firstMatch
        let frameRate = app.buttons["ready.Frame Rate"]
        for _ in 0..<8 where !row.exists && !frameRate.exists { app.swipeUp() }
        if row.exists { delete(row, in: app) }
        for _ in 0..<6 where !frameRate.exists || !frameRate.isHittable { app.swipeUp() }
        XCTAssertTrue(frameRate.exists, "no ready-made Frame Rate")
        do {
            photo("parity-1-ready-made")
            frameRate.tap()
            sleep(1)
            XCTAssertFalse(app.buttons["ready.Frame Rate"].exists, "Frame Rate is still offered after adding it")
            // Its list arrived filled: back to Film Settings, where Lists count.
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let list = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Frame Rate'")).firstMatch
            XCTAssertTrue(list.waitForExistence(timeout: 5), "Frame Rate is not among the lists")
            XCTAssertTrue(list.label.hasSuffix("6"), "Frame Rate arrived without its six rates: \(list.label)")
            photo("parity-2-frame-rate-list")
            edit.tap()
        }
        // Put it back: delete the column.
        sleep(1)
        for _ in 0..<8 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.exists, "the Frame Rate column is not on the list to delete")
        delete(row, in: app)
        for _ in 0..<6 where !frameRate.exists || !frameRate.isHittable { app.swipeUp() }
        XCTAssertTrue(frameRate.exists, "Frame Rate is not offered again")
    }

    private func delete(_ row: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !row.isHittable { app.swipeDown() }
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Delete'")).element(boundBy: 0)
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        sleep(1)
        XCTAssertFalse(row.exists, "the test column did not go")
    }

    func testDayOrderMenu() {
        let app = open()
        app.tabBars.buttons["Schedule"].tap()
        let days = app.buttons["Days"]
        if days.waitForExistence(timeout: 5) { days.tap() }
        let menu = app.buttons.matching(identifier: "Day").firstMatch
        guard menu.waitForExistence(timeout: 5) else {
            photo("parity-3-no-days"); XCTFail("no shoot day to try on"); return
        }
        menu.tap()
        XCTAssertTrue(app.buttons["Put Days in Date Order"].waitForExistence(timeout: 3)
                      || app.buttons["Move Later"].exists,
                      "the day menu has no order")
        photo("parity-3-day-menu")
        app.tap()
    }

    func testInsideOutsideTakesAnyWord() {
        let app = open()
        let scene = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '3, '")).firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 5), "no scene 3 on the list")
        scene.tap()
        // A storyboard left over from an earlier run: back to the list.
        if app.buttons["List"].exists { app.buttons["List"].firstMatch.tap() }
        let more = app.buttons["Edit"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "no scene menu")
        more.tap()
        let details = app.buttons["Scene…"]
        XCTAssertTrue(details.waitForExistence(timeout: 3), "no Scene… in the scene's menu")
        details.tap()
        let add = app.buttons["Add Inside / Outside"]
        // A run that died before tidying: put scene 3 back to EXT first.
        if add.waitForExistence(timeout: 5), app.buttons["INT/EXT"].exists,
           !app.buttons["EXT"].isSelected { app.buttons["EXT"].firstMatch.tap(); sleep(1) }
        guard add.exists else {
            photo("parity-4-no-scene-page"); XCTFail("no Inside / Outside add on the scene page"); return
        }
        photo("parity-4-scene-page")
        add.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        // A word off the three: the engine reads EXT/INT as both ways
        // (its INT/EXT ruling), so it lands as INT/EXT.
        field.typeText("EXT/INT")
        app.buttons["Add"].tap()
        sleep(1)
        photo("parity-5-typed")
        // Time of Day takes a word of its own, as on the Mac.
        app.buttons["Add Time of Day"].tap()
        let time = app.textFields.firstMatch
        XCTAssertTrue(time.waitForExistence(timeout: 3))
        time.typeText("MAGIC HOUR")
        app.buttons["Add"].tap()
        sleep(1)
        XCTAssertTrue(app.buttons["MAGIC HOUR"].waitForExistence(timeout: 3), "a typed time of day did not land")
        photo("parity-6-magic-hour")
        // Back to what scene 3 says: EXT, DAY.
        app.buttons["EXT"].firstMatch.tap()
        app.buttons["DAY"].firstMatch.tap()
        sleep(1)
    }

    /// A checkmark column ticks in Editing, as on the Mac. Adds the ready-made
    /// Covered, ticks the first shot and unticks it, and takes the column away.
    func testCheckmarkTicks() {
        let app = open()
        func columns() {
            app.buttons["film.menu"].tap()
            app.buttons["film.settings"].tap()
            let edit = app.buttons["Edit Columns"]
            XCTAssertTrue(edit.waitForExistence(timeout: 5))
            edit.tap()
        }
        columns()
        let covered = app.buttons["ready.Covered"]
        let left = app.switches.matching(NSPredicate(format: "label CONTAINS 'Covered'")).firstMatch
        for _ in 0..<8 where !left.exists && !covered.exists { app.swipeUp() }
        if left.exists { delete(left, in: app) }
        for _ in 0..<8 where !covered.exists || !covered.isHittable { app.swipeUp() }
        XCTAssertTrue(covered.exists, "no ready-made Covered")
        covered.tap()
        sleep(1)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].firstMatch.tap()
        sleep(2)

        let start = app.buttons["editing.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "no way into Editing")
        start.tap()
        // The film's sheet may still be up under Film Settings; the first tap
        // only closes it.
        if !app.buttons["editing.done"].waitForExistence(timeout: 3) { sleep(1); start.tap() }
        XCTAssertTrue(app.buttons["editing.done"].waitForExistence(timeout: 5), "Editing did not open")
        let tick = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'edit.' AND label CONTAINS 'Covered'")).firstMatch
        for _ in 0..<6 where !tick.exists || !tick.isHittable { app.swipeUp() }
        XCTAssertTrue(tick.exists, "Editing has no Covered to tick")
        tick.tap()
        sleep(1)
        XCTAssertTrue(tick.label.contains("✓"), "a tap did not tick Covered: \(tick.label)")
        photo("parity-7-ticked")
        tick.tap()
        sleep(1)
        XCTAssertFalse(tick.label.contains("✓"), "a second tap did not untick it")
        app.buttons["editing.done"].tap()
        sleep(1)

        // Take the column away again.
        columns()
        let row = app.switches.matching(NSPredicate(format: "label CONTAINS 'Covered'")).firstMatch
        for _ in 0..<8 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.exists)
        delete(row, in: app)
    }
}
