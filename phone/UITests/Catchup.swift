import XCTest

/// **The iPhone catch-up batch** (2026-10-09, his list): scene filters and
/// scene order, the Cameras page, colours, master shots, Versions. Each test
/// puts Call Her Back back the way it found it.
final class Catchup: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    func photo(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let keep = XCTAttachment(screenshot: shot)
        keep.name = name
        keep.lifetime = .keepAlways
        add(keep)
        if let out = ProcessInfo.processInfo.environment["SHOTS_OUT"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
        }
    }

    func open() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--film", "CHB", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["film.menu"].waitForExistence(timeout: 20), "no film menu")
        return app
    }

    private func sceneCount(_ app: XCUIApplication) -> Int {
        let scenes = app.buttons["scenes"]
        XCTAssertTrue(scenes.waitForExistence(timeout: 5), "no Scenes button")
        scenes.tap()
        let rows = app.buttons.matching(identifier: "scenes.row")
        _ = rows.firstMatch.waitForExistence(timeout: 5)
        let n = rows.count
        app.buttons["Done"].tap()
        sleep(1)
        return n
    }

    func testSceneFiltersAndOrder() {
        let app = open()
        let before = sceneCount(app)

        app.buttons["display"].tap()
        let filter = app.buttons["display.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        let time = app.buttons["filter.scene.time_of_day"]
        XCTAssertTrue(time.waitForExistence(timeout: 5), "no Time of Day under Scenes in Filter")
        photo("catchup-1-scene-filters")
        time.tap()
        let night = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'NIGHT'")).firstMatch
        XCTAssertTrue(night.waitForExistence(timeout: 5), "Time of Day offers no NIGHT")
        night.tap()
        sleep(1)
        XCTAssertTrue(filter.label.contains("1"), "Filter does not count the scene filter: \(filter.label)")
        photo("catchup-2-filtered")

        // Shoot day: the menu offers Not Scheduled Yet.
        filter.tap()
        let day = app.buttons["filter.scene.day"]
        XCTAssertTrue(day.waitForExistence(timeout: 5), "no Shoot Day under Scenes in Filter")
        day.tap()
        XCTAssertTrue(app.buttons["Not Scheduled Yet"].waitForExistence(timeout: 3), "no Not Scheduled Yet")
        app.buttons["Any Shoot Day"].tap()
        sleep(1)

        // Scene Order: by Location.
        let order = app.buttons["display.sceneorder"]
        XCTAssertTrue(order.waitForExistence(timeout: 3), "no Scene Order")
        order.tap()
        app.buttons["Location"].firstMatch.tap()
        sleep(1)
        photo("catchup-3-by-location")
        app.buttons["Done"].tap()
        sleep(1)
        let after = sceneCount(app)
        XCTAssertLessThan(after, before, "a NIGHT filter left every scene: \(after) of \(before)")
        photo("catchup-4-list")

        app.buttons["display"].tap()
        app.buttons["display.clear"].tap()
        sleep(1)
        app.buttons["Done"].tap()
        sleep(1)
        XCTAssertEqual(sceneCount(app), before, "Clear did not bring every scene back")
    }

    private func settings(_ app: XCUIApplication) {
        app.buttons["film.menu"].tap()
        let settings = app.buttons["film.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
    }

    func testCamerasPage() {
        let app = open()
        settings(app)
        let cameras = app.buttons["settings.cameras"]
        for _ in 0..<6 where !cameras.exists || !cameras.isHittable { app.swipeUp() }
        XCTAssertTrue(cameras.exists, "no Cameras in Film Settings")
        cameras.tap()
        app.buttons["Add Camera"].tap()
        app.textFields.firstMatch.typeText("Test Cam")
        app.buttons["Add"].tap()
        let row = app.descendants(matching: .any)["camera.Test Cam"]
        XCTAssertTrue(row.waitForExistence(timeout: 3), "the added camera is not on the page")
        // Recolour from its swatch.
        app.buttons["Color Test Cam"].tap()
        app.buttons["Green"].tap()
        sleep(1)
        photo("catchup-5-cameras")
        // Rename.
        app.staticTexts["Test Cam"].swipeLeft()
        app.buttons["Rename"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.clearAndType("Test Cam Two")
        app.alerts.buttons["Rename"].tap()
        let renamed = app.descendants(matching: .any)["camera.Test Cam Two"]
        XCTAssertTrue(renamed.waitForExistence(timeout: 3), "rename did not land")
        // Delete, with the cost said first.
        app.staticTexts["Test Cam Two"].swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Delete'")).element(boundBy: 0)
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No shot uses it."].exists, "the delete does not say its cost")
        confirm.tap()
        sleep(1)
        XCTAssertFalse(renamed.exists, "the camera did not go")
    }

    func testTermColour() {
        let app = open()
        settings(app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Shot Size'")).firstMatch.tap()
        let menu = app.buttons["Colour W"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "no colour on the list's W")
        menu.tap()
        // The second swatch (the menu rows are pictures with a space).
        let swatches = app.buttons.matching(NSPredicate(format: "label == ' ' OR label == ''"))
        XCTAssertGreaterThan(swatches.count, 1, "no swatches in the colour menu")
        swatches.element(boundBy: 1).tap()
        sleep(1)
        photo("catchup-6-term-colour")
        // Back to Automatic.
        menu.tap()
        app.buttons["Automatic"].tap()
        sleep(1)
    }

    func testHighlightAndMaster() {
        let app = open()
        let first = app.staticTexts["1A"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        // A run that died before tidying: put 1B and 1A back first.
        if app.descendants(matching: .any)["Stands in for 1A"].exists {
            app.staticTexts["1B"].firstMatch.press(forDuration: 1.2)
            app.buttons["Unlink from 1A"].tap(); sleep(1)
        }
        if app.descendants(matching: .any)["Master"].exists {
            first.press(forDuration: 1.2)
            app.buttons["Remove Master"].tap(); sleep(1)
        }
        first.press(forDuration: 1.2)
        let highlight = app.buttons["shot.highlight"]
        XCTAssertTrue(highlight.waitForExistence(timeout: 3), "no Highlight when holding a shot")
        highlight.tap()
        app.buttons["Orange"].tap()
        sleep(1)
        photo("catchup-7-highlight")

        first.press(forDuration: 1.2)
        app.buttons["Make Master"].tap()
        sleep(1)
        XCTAssertTrue(app.descendants(matching: .any)["Master"].waitForExistence(timeout: 3), "no master mark on 1A")

        let second = app.staticTexts["1B"].firstMatch
        second.press(forDuration: 1.2)
        let link = app.buttons["Link to Master"]
        XCTAssertTrue(link.waitForExistence(timeout: 3), "no Link to Master")
        link.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '1A'")).firstMatch.tap()
        sleep(1)
        photo("catchup-8-master-link")
        XCTAssertTrue(app.descendants(matching: .any)["Stands in for 1A"].exists, "1B does not say it stands in for 1A")

        // Put it all back.
        app.staticTexts["1B"].firstMatch.press(forDuration: 1.2)
        app.buttons["Unlink from 1A"].tap()
        sleep(1)
        first.press(forDuration: 1.2)
        app.buttons["Remove Master"].tap()
        sleep(1)
        first.press(forDuration: 1.2)
        app.buttons["shot.highlight"].tap()
        app.buttons["No Highlight"].tap()
        sleep(1)
        XCTAssertFalse(app.descendants(matching: .any)["Stands in for 1A"].exists, "the link did not come off")
    }

    /// Save a version, change a shot, look at the old one (banner, Bring
    /// Back Shot), back to now, then Go Back and see the change undone.
    /// Deletes the versions it made.
    func testVersions() {
        let app = open()
        let stamp = "Catchup \(Int(Date().timeIntervalSince1970) % 100000)"
        // Start with 1A plain, whatever an earlier run left.
        app.staticTexts["1A"].firstMatch.press(forDuration: 1.2)
        app.buttons["shot.highlight"].tap()
        if app.buttons["No Highlight"].exists { app.buttons["No Highlight"].tap() } else { app.tap() }
        sleep(1)
        func versions() {
            app.buttons["film.menu"].tap()
            let row = app.buttons["film.versions"]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "no Versions on the film menu")
            row.tap()
        }
        versions()
        app.buttons["Save Version"].tap()
        app.textFields.firstMatch.typeText(stamp)
        app.buttons["Save"].tap()
        let saved = app.buttons["version.\(stamp)"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "the saved version is not listed")
        photo("catchup-9-versions")
        app.buttons["Done"].tap()
        sleep(1)
        // The film's menu is still up under it; drag it away.
        app.swipeDown(velocity: .fast)
        sleep(1)

        // Change something: highlight 1A.
        let first = app.staticTexts["1A"].firstMatch
        first.press(forDuration: 1.2)
        app.buttons["shot.highlight"].tap()
        app.buttons["Purple"].tap()
        sleep(1)

        // Look at the old one.
        app.buttons["film.menu"].tap()
        app.buttons["film.versions"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        let now = app.buttons["version.now"]
        XCTAssertTrue(now.waitForExistence(timeout: 5), "no banner while looking at a version")
        first.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Bring Back Shot"].waitForExistence(timeout: 3), "no Bring Back Shot while looking")
        photo("catchup-10-looking")
        app.buttons["Bring Back Shot"].tap()
        sleep(1)
        XCTAssertFalse(now.exists, "bringing back did not return to now")

        // Highlight again, then Go Back whole.
        first.press(forDuration: 1.2)
        app.buttons["shot.highlight"].tap()
        XCTAssertFalse(app.buttons["No Highlight"].exists, "Bring Back Shot did not take the highlight off 1A")
        app.buttons["Purple"].tap()
        sleep(1)
        versions()
        saved.press(forDuration: 1.2)
        app.buttons["Go Back to This Version…"].tap()
        let go = app.buttons.matching(NSPredicate(format: "label == 'Go Back'")).firstMatch
        XCTAssertTrue(go.waitForExistence(timeout: 3))
        go.tap()
        sleep(3)
        first.press(forDuration: 1.2)
        app.buttons["shot.highlight"].tap()
        XCTAssertFalse(app.buttons["No Highlight"].exists, "Go Back did not take the highlight off 1A")
        app.tap()
        sleep(1)

        // Tidy: delete the versions this made (his and the one Go Back kept).
        versions()
        for _ in 0..<8 {
            let mine = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'version.Catchup' OR label CONTAINS 'Automatic'")).firstMatch
            guard mine.exists else { break }
            mine.swipeLeft()
            app.buttons["Delete"].firstMatch.tap()
            let confirm = app.buttons.matching(NSPredicate(format: "label == 'Delete'")).element(boundBy: 0)
            if confirm.waitForExistence(timeout: 3) { confirm.tap() }
            sleep(1)
        }
        XCTAssertFalse(saved.exists, "the test version is still listed")
    }
}

extension XCUIElement {
    func clearAndType(_ text: String) {
        tap()
        if let value = value as? String, !value.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        typeText(text)
    }
}
