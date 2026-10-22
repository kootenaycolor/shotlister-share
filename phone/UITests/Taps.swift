import XCTest

/// **The half of checking a simulator cannot do by itself.**
///
/// `checks.sh` runs the phone's own decoder over his real projects and draws
/// nothing; `--film` and `--shotpage` open any screen for a photograph. What
/// neither can do is press anything, so the look pass of 2026-10-07 shipped
/// with two things unproven: whether the Shot mark actually marks a shot, and
/// whether the last row of a list clears the new bar at the bottom.
///
/// These press them. Everything runs against Call Her Back, his real film, in
/// whatever simulator is booted.
final class Taps: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func open(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// `2026-10-07`, local: the day a hand choice of the marks is for.
    private static var today: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// **The marks keep off the list except on a shoot day**, and the View
    /// menu turns them on (his ask, 2026-10-07). Call Her Back shoots in
    /// November, so today is not one of its days.
    func testShotMarksHiddenOffAShootDayAndSwitchedOn() {
        let app = open(["--film", "CHB", "0"])
        let mark = app.buttons.matching(identifier: "shotmark").element(boundBy: 0)
        let view = app.buttons["display"]
        XCTAssertTrue(view.waitForExistence(timeout: 20), "no Display button")
        func flip() {
            view.tap()
            let toggle = app.switches["Mark Shots"].exists ? app.switches["Mark Shots"] : app.buttons["Mark Shots"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no Mark Shots in Display")
            // The switch itself, at the row's right: a Form row's label
            // does not flip it.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            app.buttons["Done"].tap()
            sleep(1)
        }
        // A run before may have switched them on for today; off first.
        if mark.waitForExistence(timeout: 3) { flip() }
        sleep(1)
        XCTAssertFalse(mark.exists, "Mark Shots off did not put the marks away")
        flip()
        XCTAssertTrue(mark.waitForExistence(timeout: 5), "Mark Shots did not bring the marks out")
        // Put it back as he would find it: off, on a day that is not a shoot day.
        flip()
        sleep(1)
        XCTAssertFalse(mark.exists, "the marks stayed after Mark Shots went off")
    }

    /// **A shot can be marked Shot, and unmarked.** The verb was reachable
    /// only through a multi-select and a bulk edit before; this is the one
    /// tap that replaced it.
    func testShotMarkStrikesAndUnstrikes() {
        // Call Her Back's days are not today, so the marks are switched on
        // for today by hand, the way the View menu stores it.
        let app = open(["--film", "CHB", "0", "-shotlist.marks", "on:\(Self.today)"])
        XCTAssertTrue(app.buttons.matching(identifier: "shotmark").element(boundBy: 0)
                        .waitForExistence(timeout: 20), "no Shot mark on the shot list")

        // The row carries the identifier too, because a List merges its
        // children into one element. The circle is the small one.
        func circle() -> XCUIElement {
            app.buttons.matching(identifier: "shotmark").allElementsBoundByIndex
                .first { $0.frame.width < 60 } ?? app.buttons["shotmark"]
        }
        let first = circle()
        let wasShot = first.label == "Not Shot Yet"
        first.tap()

        // The label is the state: "Shot" invites marking, "Not Shot Yet"
        // invites putting it back.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(circle().label, wasShot ? "Shot" : "Not Shot Yet",
                       "the mark did not change the shot's state")

        // **And back, so the film is left exactly as it was found.** A test
        // that marks a real shot and walks away is a test that edits his
        // film; this one puts it back and checks that it did.
        circle().tap()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(circle().label, wasShot ? "Not Shot Yet" : "Shot",
                       "the shot was left in the wrong state")
    }

    /// **The last row of a long list clears the bar.** The tab bar reserves
    /// that room; it stopped being reserved for one afternoon when the bar
    /// was a floating pill, and every list ended under glass.
    func testTheEndOfALongListIsNotUnderTheBar() {
        let app = open(["--film", "CHB", "5"])
        // The tab bar reserves the room. Measure against the Library tab,
        // which is the thing actually sitting at the bottom of the screen.
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 20), "no bar at the bottom")

        // To the bottom, then a moment for the bounce to settle.
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<12 { scroll.swipeUp(velocity: .fast) }
        Thread.sleep(forTimeInterval: 1.5)

        // The lowest row that is still on screen must sit above the bar.
        // Labelled rows only: the hidden tab bar leaves nameless elements
        // sitting at the foot of the screen that are not content.
        let rows = app.buttons.allElementsBoundByIndex
            .filter { $0.exists && !$0.label.isEmpty && $0.frame.height > 20
                      && !bar.frame.contains($0.frame.origin) }
        guard let lowest = rows.max(by: { $0.frame.maxY < $1.frame.maxY }) else {
            return XCTFail("nothing on the Library to measure")
        }
        XCTAssertLessThanOrEqual(lowest.frame.maxY, bar.frame.minY + 1,
                                 "the last row (\(lowest.label)) runs under the bar")
    }
}
