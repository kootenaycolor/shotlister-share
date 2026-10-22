import XCTest

/// **A real press on an Edit Reference's gold play button.** Skips itself
/// unless /tmp/editref-tap-on exists, so taps.sh is unaffected. The scratch
/// film `ECT` (one edit reference over 34C-35A) goes in the simulator's
/// Documents first.
final class EditRefTap: XCTestCase {
    func testPlayButtonOpensThePlayer() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/tmp/editref-tap-on"))
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--film", "ECT", "0", "--modson", "edit_reference"]
        app.launch()
        let play = app.buttons["editref.play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 25), "no play button")
        play.tap()
        let close = app.buttons["editref.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "the press on play did not open the player")
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/ec/phone-player.png"))
        close.tap()
        XCTAssertTrue(play.waitForExistence(timeout: 8), "the player did not close")
    }
}
