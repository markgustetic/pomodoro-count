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

        // A throwaway store, seeded by the app itself, so these tests can never
        // read or write the real pomodoro history.
        //
        // Run as a plain subprocess rather than through `XCUIApplication`:
        // `--seed-store` writes the file and exits immediately, and XCUITest
        // treats an app that exits during launch as a launch failure.
        storePath = NSTemporaryDirectory()
            + "pomodoro-uitest-\(UUID().uuidString)/data.json"
        let seeder = Process()
        seeder.executableURL = try Self.appBinary()
        seeder.arguments = ["--seed-store", storePath]
        try seeder.run()
        seeder.waitUntilExit()
        XCTAssertTrue(FileManager.default.fileExists(atPath: storePath),
                      "seeding did not write \(storePath!)")

        app = XCUIApplication()
        app.launchArguments = ["--store", storePath]
        app.launch()

        try openSettings()
    }

    override func tearDown() {
        app?.terminate()
    }

    /// The app binary in the built-products directory.
    ///
    /// Walked up to rather than hardcoded: the test bundle sits several levels
    /// inside `UITests-Runner.app`, and how many is Xcode's business, not this
    /// test's.
    private static func appBinary() throws -> URL {
        var dir = Bundle(for: CategoryReorderUITests.self).bundleURL
        for _ in 0..<6 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir.appendingPathComponent("PomodoroCount.app/Contents/MacOS/PomodoroCount")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        throw XCTSkip("PomodoroCount.app not found near \(Bundle(for: CategoryReorderUITests.self).bundleURL.path)")
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

    /// The order as persisted, read straight out of the store the app writes.
    ///
    /// The drag commits on drop, and this panel dismisses the moment it loses
    /// focus — which posting mouse events can cause — so the live element tree
    /// is not reliably there to read afterwards. The store is, and it is also
    /// the thing that has to be right: an order that never reached disk would
    /// look identical until the next launch.
    private func persistedOrder() throws -> [String] {
        let data = try Data(contentsOf: URL(fileURLWithPath: storePath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let settings = json?["settings"] as? [String: Any]
        let categories = settings?["categories"] as? [[String: Any]] ?? []
        return categories.compactMap { $0["name"] as? String }
    }

    private func expect(persisted expected: [String],
                        file: StaticString = #filePath, line: UInt = #line) throws {
        // The write lands on drop; give it a moment rather than racing it.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && (try? persistedOrder()) != expected {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(try persistedOrder(), expected, file: file, line: line)
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
    /// The likely reason is the same property that broke two of the three
    /// reorder mechanisms this suite exists to catch: the `MenuBarExtra` panel
    /// dismisses the instant it loses first-responder status. Element-based
    /// clicks fail outright with "no longer valid after interruption handling",
    /// and synthetic mouse events appear to close it too. So the automation
    /// keeps closing the thing it is trying to drag.
    ///
    /// Ideas not yet tried, roughly in order of promise: keeping the app
    /// activated for the length of the drag (`NSApp.activate` behind a debug
    /// flag, the way `MenuBarPanel.present()` already does at launch); posting
    /// events to `.cgSessionEventTap` rather than `.cghidEventTap`; or an
    /// in-app debug command that runs the gesture's own code path so the test
    /// exercises the state machine without needing a real pointer.
    private func skipUntilDragAutomationWorks() throws {
        throw XCTSkip("Drag automation does not yet drive this panel — see the note above.")
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
