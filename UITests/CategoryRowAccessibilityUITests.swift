import XCTest

/// What VoiceOver actually gets from a Focus-tab category row.
///
/// `AccessibilityTests` already covers `CategoryProgress.accessibilityValue` as
/// a string, and passes — but a correct string proves nothing about what the
/// Accessibility API ends up vending, and that gap is exactly where this bug
/// lived: the row set `.accessibilityValue(…)` and VoiceOver got no value at
/// all, because `.accessibilityElement(children: .ignore)` applied *to* a
/// `Button` throws the button's own element away and builds a plain one in its
/// place. A generic element has no `AXValue` attribute, so the macOS bridge
/// demotes the string to `AXValueDescription`, and no button role means no
/// `AXPress` either — the row could not be activated at all.
///
/// So these assert on the AX tree, not on a Swift string. XCUITest is the only
/// suite in this project that can see it: `app.buttons[…]` resolves by AX role,
/// and `.value` reads `AXValue`. Both would pass vacuously against a plain
/// element if written as `app.descendants(…)`, which is why the role is asserted
/// by *querying* for a button rather than by reading a role property.
final class CategoryRowAccessibilityUITests: XCTestCase {

    private var app: XCUIApplication!
    private var storePath: String!

    /// `StoreSeed` gives every category a daily goal of 1 and no records, so
    /// every row starts at "0 of 1 pomodoros". Asserted as a *prefix*: the
    /// target mark is appended to this string, and which row the app launches
    /// aimed at is not this test's business.
    private let expectedProgress = "0 of 1 pomodoros"

    override func setUpWithError() throws {
        continueAfterFailure = false

        storePath = try TestStore.seed()

        app = XCUIApplication()
        app.launchArguments = ["--store", storePath]
        app.launch()

        try openPanel()
    }

    override func tearDown() {
        app?.terminate()
    }

    /// The app's own status item — the small strip out at the right-hand end,
    /// picked by frame the way `CategoryReorderUITests` does, since index order
    /// is not promised.
    private var statusItem: XCUIElement {
        let bars = app.menuBars
        for i in 0..<bars.count where bars.element(boundBy: i).frame.origin.x > 0 {
            return bars.element(boundBy: i)
        }
        return bars.element(boundBy: bars.count - 1)
    }

    /// Opens the panel and leaves it on the Focus tab, which is where it lands.
    ///
    /// Clicked by coordinate rather than `XCUIElement.click()`: this panel
    /// dismisses the instant it loses first-responder status, and XCUITest's
    /// interruption handling closes the very thing it is about to click.
    private func openPanel() throws {
        XCTAssertTrue(statusItem.waitForExistence(timeout: 20), "no status item appeared")
        statusItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    // MARK: Tests

    /// The row is a button to the Accessibility API, not an anonymous shape.
    ///
    /// This is the assertion that fails loudest against the bug: the element was
    /// `AXUnknown`, so `app.buttons["Alpha"]` never resolved at all.
    func testACategoryRowIsAButton() {
        XCTAssertTrue(app.buttons["Alpha"].waitForExistence(timeout: 10),
                      "the Focus tab has no button labelled Alpha — the row is not a button to VoiceOver")
    }

    /// The progress string reaches `AXValue`, which is what VoiceOver speaks
    /// after the label.
    func testACategoryRowSpeaksItsProgress() {
        let row = app.buttons["Alpha"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no button labelled Alpha")
        XCTAssertTrue((row.value as? String)?.hasPrefix(expectedProgress) == true,
                      "wrong value on Alpha: \(String(describing: row.value))")
    }

    /// Every row, not just the first: the value is built per row, and a bug that
    /// wired only one of them up would otherwise pass.
    func testEveryCategoryRowSpeaksItsProgress() {
        for name in ["Alpha", "Bravo", "Charlie", "Delta"] {
            let row = app.buttons[name]
            XCTAssertTrue(row.waitForExistence(timeout: 10), "no button labelled \(name)")
            XCTAssertTrue((row.value as? String)?.hasPrefix(expectedProgress) == true,
                          "wrong value on \(name): \(String(describing: row.value))")
        }
    }

    /// Activating a row aims the session target at it — the row's own job now
    /// that the dropdown is gone. Asserted through `AXValue`, because the
    /// outline that says the same thing to the eye is invisible to this API.
    ///
    /// Bravo rather than Alpha: whichever row the app launches aimed at, it can
    /// only be the first unmet one or the bucket, never the second category. So
    /// clicking Bravo is always a real move.
    func testActivatingARowAimsTheTargetAtIt() {
        let bravo = app.buttons["Bravo"]
        XCTAssertTrue(bravo.waitForExistence(timeout: 10), "no button labelled Bravo")
        XCTAssertTrue(bravo.isHittable, "the row reports no activation point")
        bravo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        XCTAssertTrue((bravo.value as? String)?.hasSuffix(", session target") == true,
                      "activating the row did not aim the target at it: \(String(describing: bravo.value))")
        XCTAssertFalse((app.buttons["Alpha"].value as? String)?.hasSuffix(", session target") == true,
                       "the mark stayed on Alpha as well")
    }

    /// Activating a row must *not* open the counter. That was the old
    /// behaviour, and the whole point of moving counting onto its own control
    /// was to give the row back to the commoner action.
    func testActivatingARowDoesNotOpenTheCounter() {
        let bravo = app.buttons["Bravo"]
        XCTAssertTrue(bravo.waitForExistence(timeout: 10), "no button labelled Bravo")
        bravo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        XCTAssertFalse(app.buttons["Add one pomodoro to Bravo"].exists,
                       "clicking the row raised the count popover")
    }

    /// The ± is its own element with its own role, not decoration inside the
    /// row — which is what it would be if it were nested in the row button's
    /// label rather than sitting beside it.
    func testTheAdjustGlyphIsItsOwnButtonAndOpensTheCounter() {
        let adjust = app.buttons["Adjust today's count for Alpha"]
        XCTAssertTrue(adjust.waitForExistence(timeout: 10),
                      "the row has no separate adjust button")
        XCTAssertTrue(adjust.isHittable, "the adjust button reports no activation point")
        adjust.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        XCTAssertTrue(app.buttons["Add one pomodoro to Alpha"].waitForExistence(timeout: 10),
                      "the adjust button did not raise the count popover")
    }
}
