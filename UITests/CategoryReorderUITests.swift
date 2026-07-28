import XCTest

/// Drives the real app: clicks the real menu bar item, opens the real panel,
/// and drags a real grip.
///
/// This target exists because three reorder mechanisms were tried and two of
/// them did nothing at all, and neither the unit suite, the build, nor a
/// rendered screenshot caught either — only a person with a mouse did.
///
/// It deliberately does not use a test harness window. One was written first: a
/// hand-built `NSPanel` meant to imitate the one `MenuBarExtra` puts the UI in.
/// It was abandoned because its fidelity could not be established. Getting that
/// imitation wrong in the permissive direction — an ordinary key window — would
/// produce a suite that passed for reorder mechanisms known to be broken, which
/// is worse than having no suite at all, because it converts "untested" into
/// "tested and fine". Driving the real menu bar item removes the question.
final class CategoryReorderUITests: XCTestCase {

    private var app: XCUIApplication!
    private var storePath: String!

    /// Matches `StoreSeed.categories`.
    private let startingOrder = ["Alpha", "Bravo", "Charlie", "Delta"]

    override func setUpWithError() throws {
        continueAfterFailure = false

        storePath = try TestStore.seed()

        app = XCUIApplication()
        app.launchArguments = ["--store", storePath]
        app.launch()

        try openSettings()
    }

    override func tearDown() {
        app?.terminate()
    }

    // MARK: Reaching the UI

    /// The app's own status item. `menuBars` holds two elements: the system menu
    /// bar at the origin, and ours — a small strip out at the right-hand end.
    /// Picking by frame rather than by index, since index order is not promised.
    private var statusItem: XCUIElement {
        let bars = app.menuBars
        for i in 0..<bars.count where bars.element(boundBy: i).frame.origin.x > 0 {
            return bars.element(boundBy: i)
        }
        return bars.element(boundBy: bars.count - 1)
    }

    private func openSettings() throws {
        XCTAssertTrue(statusItem.waitForExistence(timeout: 20), "no status item appeared")
        tap(statusItem)

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10),
                      "the panel did not open, or has no Settings tab")
        tap(settings)

        XCTAssertTrue(row("Alpha").waitForExistence(timeout: 10),
                      "Settings opened but the seeded categories are not there")
    }

    /// Clicks the centre of an element by coordinate rather than calling
    /// `click()` on it.
    ///
    /// `XCUIElement.click()` re-resolves the element and runs XCUITest's
    /// interruption handling, and this panel dismisses the instant it loses
    /// first-responder status — so that machinery closes the very thing it is
    /// about to click, and the click fails with "no longer valid after
    /// interruption handling". A coordinate resolves once and then sends a
    /// plain event at a screen point, which is what a hand does.
    private func tap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    // MARK: Reading and driving

    /// A row, by the accessibility label `CategoryList` puts on it.
    private func row(_ name: String) -> XCUIElement {
        app.groups[name]
    }

    /// The visible order, read off the rows' own vertical positions. Reading
    /// the model would prove nothing about what the user sees.
    private var order: [String] {
        startingOrder
            .map { ($0, row($0).frame.origin.y) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// A drag posted as a real stream of mouse events.
    ///
    /// `XCUICoordinate.press(forDuration:thenDragTo:)` does not drive this
    /// gesture, at any velocity — SwiftUI's `DragGesture` needs a genuine
    /// sequence of `mouseDragged` events past its minimum distance, and
    /// XCUITest's synthesis is too coarse. Posting the events directly is what a
    /// hand does: move, press, forty small drags, release.
    ///
    /// Coordinates are screen points, origin top-left, which is what both
    /// `XCUIElement.frame` and `CGEvent` use here.
    private func drag(from start: CGPoint, to end: CGPoint, steps: Int = 40) {
        let source = CGEventSource(stateID: .hidSystemState)

        func post(_ type: CGEventType, _ point: CGPoint) {
            CGEvent(mouseEventSource: source,
                    mouseType: type,
                    mouseCursorPosition: point,
                    mouseButton: .left)?.post(tap: .cghidEventTap)
        }

        post(.mouseMoved, start)
        usleep(120_000)
        post(.leftMouseDown, start)
        usleep(150_000)
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t,
                                            y: start.y + (end.y - start.y) * t))
            usleep(15_000)
        }
        usleep(200_000)
        post(.leftMouseUp, end)
        usleep(200_000)
    }

    /// A point inside a row's grip: a 12pt glyph at the row's leading edge.
    private func gripPoint(_ name: String) -> CGPoint {
        let f = row(name).frame
        return CGPoint(x: f.minX + 6, y: f.midY)
    }

    private func centrePoint(_ name: String) -> CGPoint {
        let f = row(name).frame
        return CGPoint(x: f.midX, y: f.midY)
    }

    /// Asserts on the store rather than the element tree: the drag commits on
    /// drop, and this panel dismisses the moment it loses focus — which posting
    /// mouse events can cause — so the live tree is not reliably there to read
    /// afterwards.
    private func expect(persisted expected: [String],
                        file: StaticString = #filePath, line: UInt = #line) throws {
        try TestStore.expectOrder(expected, at: storePath, file: file, line: line)
    }

    // MARK: Tests

    /// Where this got to, so the next person does not rediscover it.
    ///
    /// The drag tests below are skipped, not deleted, and not passing. Driving
    /// the app this far works: the status item clicks, the panel opens, Settings
    /// opens, and the seeded rows render in order — `testTheSeededCategoriesAppearInOrder`
    /// proves all of that. What does not work is the drag itself. Neither
    /// `XCUICoordinate.press(forDuration:thenDragTo:withVelocity:)` at any
    /// velocity, nor a hand-posted stream of `CGEvent` mouse-down / forty
    /// mouse-dragged / mouse-up, moves a row — while the same drag by hand
    /// does.
    ///
    /// Later investigation (2026-07-28, the coordinate-space stutter) narrowed
    /// this down. Posted `CGEvent` streams were retried against the panel at
    /// both `.cghidEventTap` and `.cgSessionEventTap`, with click-state and
    /// delta fields filled in the way hardware fills them: clicks reach the
    /// panel's buttons, and the panel does not close, but the gesture never
    /// fires — not one `onChanged`. The identical stream drives the identical
    /// view perfectly in an ordinary window, which is how the stutter was
    /// finally measured and fixed. So the panel-specific blocker is real but
    /// it is not dismissal; whatever `MenuBarExtra`'s panel does with
    /// synthetic mouse-down streams, it does before SwiftUI's gesture sees
    /// them.
    ///
    /// `--reorder-window` (`ReorderHarness`) hosts the panel's UI in a plain
    /// window for exactly this: reorder *dynamics* — tracking, one commit per
    /// crossing, no spurious reverts — can be driven and asserted there, and
    /// `ReorderDynamicsTests` does. What it can never prove is that a drag
    /// *starts* in the real panel; an ordinary key window is permissive in
    /// precisely the way that made two AppKit-drag mechanisms look plausible
    /// while being dead here. That last inch stays with a person and a mouse.
    private func skipUntilDragAutomationWorks() throws {
        throw XCTSkip("Synthetic drags do not drive the panel's gesture (a plain window works — see the note above).")
    }


    func testTheSeededCategoriesAppearInOrder() {
        XCTAssertEqual(order, startingOrder)
    }

    /// The headline case, and the one that would have failed for both broken
    /// mechanisms. That is the entire reason this target exists.
    func testDraggingARowDownReordersIt() throws {
        try skipUntilDragAutomationWorks()
        drag(from: gripPoint("Alpha"), to: centrePoint("Charlie"))
        try expect(persisted: ["Bravo", "Charlie", "Alpha", "Delta"])
    }

    func testDraggingARowUpReordersIt() throws {
        try skipUntilDragAutomationWorks()
        drag(from: gripPoint("Delta"), to: centrePoint("Bravo"))
        try expect(persisted: ["Alpha", "Delta", "Bravo", "Charlie"])
    }

    /// A press on the grip that does not move must not reorder anything — the
    /// gesture carries a minimum distance for exactly this.
    func testAStationaryPressChangesNothing() throws {
        try skipUntilDragAutomationWorks()
        drag(from: gripPoint("Bravo"), to: gripPoint("Bravo"))
        try expect(persisted: startingOrder)
    }

    /// Dragging the name field must not reorder. The row is a text field, a
    /// stepper and a button edge to edge, and keeping those working is why the
    /// drag is confined to the grip.
    func testDraggingTheNameFieldDoesNotReorder() throws {
        try skipUntilDragAutomationWorks()
        drag(from: centrePoint("Alpha"), to: centrePoint("Charlie"))
        try expect(persisted: startingOrder)
    }

}
