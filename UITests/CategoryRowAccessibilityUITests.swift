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
    /// every row starts at "0 of 1 pomodoros".
    private let expectedValue = "0 of 1 pomodoros"

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
        XCTAssertEqual(row.value as? String, expectedValue)
    }

    /// Every row, not just the first: the value is built per row, and a bug that
    /// wired only one of them up would otherwise pass.
    func testEveryCategoryRowSpeaksItsProgress() {
        for name in ["Alpha", "Bravo", "Charlie", "Delta"] {
            let row = app.buttons[name]
            XCTAssertTrue(row.waitForExistence(timeout: 10), "no button labelled \(name)")
            XCTAssertEqual(row.value as? String, expectedValue, "wrong value on \(name)")
        }
    }

    /// The row can be activated, which is how a VoiceOver user opens the count
    /// popover. `AXPress` went missing with the button role — the adjustable
    /// action added by the popover work was, until this fix, the row's *only*
    /// accessibility action.
    func testACategoryRowCanBeActivated() {
        let row = app.buttons["Alpha"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no button labelled Alpha")
        XCTAssertTrue(row.isHittable, "the row reports no activation point")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        XCTAssertTrue(app.buttons["Add one pomodoro to Alpha"].waitForExistence(timeout: 10),
                      "activating the row did not raise its count popover")
    }
}
