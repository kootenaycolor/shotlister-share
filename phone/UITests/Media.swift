import XCTest

/// **Film Settings › Media** (SL-1687): the row with count and size, the
/// list biggest first, Not Used, Delete Unused, and the Deleted list.
/// **Deletes for real**: run it on a simulator's own copy of a film only.
final class Media: XCTestCase {

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

    func testMediaLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["--film", "CHB", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["film.menu"].waitForExistence(timeout: 20), "no film menu")
        app.buttons["film.menu"].tap()
        let settings = app.buttons["film.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let media = app.buttons["settings.media"]
        for _ in 0..<6 where !media.exists || !media.isHittable { app.swipeUp() }
        XCTAssertTrue(media.exists, "no Media in Film Settings")
        sleep(2)
        photo("media-1-settings")
        media.tap()

        let rows = app.descendants(matching: .any).matching(identifier: "media.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "no media rows")
        sleep(2)
        photo("media-2-all")

        app.buttons["Not Used 87"].firstMatch.tap()
        sleep(1)
        photo("media-3-unused")

        let deleteUnused = app.buttons["media.deleteunused"]
        XCTAssertTrue(deleteUnused.waitForExistence(timeout: 5), "no Delete Unused")
        deleteUnused.tap()
        sleep(1)
        photo("media-4-ask")
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete Unused'")).element(boundBy: 1)
        if confirm.exists { confirm.tap() } else {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete Unused ·'")).firstMatch.tap()
        }
        sleep(2)
        photo("media-5-after")
        XCTAssertTrue(app.buttons["Not Used 0"].waitForExistence(timeout: 5), "Delete Unused left some unused")

        app.buttons["Deleted"].firstMatch.tap()
        sleep(1)
        photo("media-6-deleted")
    }
}
