import XCTest

/// **A board's wall holds still while it scrolls** (2026-10-13). Call Her Back's
/// *Specific Compositions* went grey and changed shape tile by tile on the way
/// back up. Scrolls down and back, photographing each stop, and counts the
/// tiles still waiting once each stop has had a moment to settle.
final class BoardScroll: XCTestCase {

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

    func testBoardHoldsStill() {
        let app = XCUIApplication()
        app.launchArguments = ["--film", "CHB", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["film.menu"].waitForExistence(timeout: 20), "no film menu")
        let library = app.buttons["Library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 5), "no Library in the bar")
        library.tap()
        let shelf = app.buttons["Reference Images"].firstMatch
        XCTAssertTrue(shelf.waitForExistence(timeout: 10), "no Reference Images in the Library")
        shelf.tap()
        let board = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Specific Compositions'")).firstMatch
        for _ in 0..<4 where !board.exists { app.swipeUp() }
        XCTAssertTrue(board.waitForExistence(timeout: 10), "no Specific Compositions board")
        board.tap()
        sleep(3)
        photo("board-0-top")
        var waiting: [Int] = []
        for step in 1...4 {
            app.swipeUp(velocity: .fast)
            sleep(2)
            waiting.append(app.activityIndicators.count)
            photo("board-\(step)-down")
        }
        for step in 1...4 {
            app.swipeDown(velocity: .fast)
            sleep(2)
            waiting.append(app.activityIndicators.count)
            photo("board-\(step)-up")
        }
        print("WAITING", waiting)
        XCTAssertEqual(waiting.reduce(0, +), 0, "tiles still waiting after settling: \(waiting)")
    }
}
