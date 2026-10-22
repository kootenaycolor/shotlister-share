import XCTest

/// **Sort and Filter on the iPhone** (2026-10-09): the Display sheet carries
/// both (`design/42-one-home`), a filter takes emptied scenes off the list,
/// and a sort says so. Photographs each step into `SHOTS_OUT` when it is set.
final class SortFilter: XCTestCase {

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

    func testDisplaySheetFiltersAndSorts() {
        let app = XCUIApplication()
        app.launchArguments = ["--film", "CHB", "0"]
        app.launch()

        // How many scenes there are, read off the Scenes sheet.
        let scenes = app.buttons["scenes"]
        XCTAssertTrue(scenes.waitForExistence(timeout: 20), "no Scenes button")
        scenes.tap()
        let rows = app.buttons.matching(identifier: "scenes.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "the Scenes sheet drew no scenes")
        let before = rows.count
        photo("1-scenes-sheet")
        app.buttons["Done"].tap()
        sleep(1)

        let display = app.buttons["display"]
        XCTAssertTrue(display.waitForExistence(timeout: 5), "no Display button")
        display.tap()

        // Filter by the first lens on the list.
        let filter = app.buttons["display.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "no Filter in Display")
        filter.tap()
        let lens = app.buttons["Lens"]
        XCTAssertTrue(lens.waitForExistence(timeout: 5), "no Lens in the Filter menu")
        lens.tap()
        let value = app.buttons.matching(NSPredicate(format: "label == 'MP 18mm'")).firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 5), "the Lens menu offered no lens")
        value.tap()
        sleep(1)
        photo("2-filtered-display")
        XCTAssertTrue(filter.label.contains("1"), "Filter does not count the filter: \(filter.label)")

        // Sort by Lens from the same sheet.
        let sort = app.buttons["display.sort"]
        sort.tap()
        let byLens = app.buttons["Lens"]
        XCTAssertTrue(byLens.waitForExistence(timeout: 5), "no Lens in the Sort menu")
        byLens.tap()
        sleep(1)
        XCTAssertTrue(sort.label.contains("Lens"), "Sort does not say Lens: \(sort.label)")
        photo("3-sorted-display")

        app.buttons["Done"].tap()
        sleep(1)
        photo("4-list-filtered-sorted")
        // Fewer scenes on the Scenes sheet now.
        scenes.tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "the filtered Scenes sheet drew no scenes")
        XCTAssertLessThan(rows.count, before, "a lens filter left every scene on the sheet")
        app.buttons["Done"].tap()
        sleep(1)
        XCTAssertTrue(app.buttons["sortfilter.clear"].exists, "the list does not say it is filtered")

        app.buttons["sortfilter.clear"].tap()
        sleep(1)
        XCTAssertFalse(app.buttons["sortfilter.clear"].exists, "Clear left the list filtered")
        photo("5-cleared")
    }
}
