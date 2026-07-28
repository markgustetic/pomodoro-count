import AppKit
import ApplicationServices
import XCTest

/// Drives the drag itself, in the `--reorder-window` harness, and asserts on
/// its dynamics: one committed move per slot crossing, no spurious reverts,
/// nothing moving under a stationary press, and the store agreeing with what
/// is on screen.
///
/// This is the half of the reorder story `CategoryReorderUITests` cannot
/// reach: synthetic mouse events never start the gesture in the real panel, so
/// its drag tests are skipped, and the stutter that motivated all of this — a
/// commit and an immediate revert on every crossing — lived entirely in the
/// dynamics that follow the grab. In the harness's plain window a posted
/// `CGEvent` stream drives the identical gesture, layout and animation code.
///
/// The harness's fidelity rule (see `ReorderHarness`) is binding here: these
/// tests assert dynamics only. They must never be read — or extended — to
/// claim that a drag *starts* in the real panel; an ordinary key window
/// accepts synthetic drags the panel provably swallows. That last inch stays
/// with a person and a mouse, and the panel suite's skipped tests document it.
///
/// Rows are read through the raw Accessibility API rather than XCUITest,
/// which was measured, not preferred: an `XCUIElement` frame query snapshots
/// the whole tree and costs the better part of a second, while an
/// `AXUIElement` frame read costs about a millisecond — fast enough to sample
/// after every posted event. The AX frames also turn out to report the
/// *committed* layout, not the animation in flight: a neighbouring row's frame
/// snaps to its new slot the instant a move commits and holds still while the
/// spring plays out. That makes the sampled order a faithful record of the
/// commit sequence, which is exactly the thing under test.
///
/// This class lives in `DynamicsTests`, a plain unit-test bundle, not in the
/// XCUITest bundle beside it. Nothing here is XCUITest — no `XCUIApplication`,
/// no runner — and the distinction is what lets it run unattended: launching
/// an XCUITest runner requires Automation Mode, which this machine grants only
/// to a person authenticating at the keyboard, while posting events and
/// reading AX frames need just the Accessibility permission the invoking
/// terminal already holds.
final class ReorderDynamicsTests: XCTestCase {

    private var app: Process!
    private var storePath: String!
    private var axApp: AXUIElement!
    private var rows: [String: AXUIElement] = [:]

    /// The four slots' resting centres, top to bottom, captured before any
    /// drag. Commits are recognised by rows sitting on these.
    private var slotCenters: [CGFloat] = []

    /// Matches `StoreSeed.categories`.
    private let startingOrder = ["Alpha", "Bravo", "Charlie", "Delta"]

    override func setUpWithError() throws {
        continueAfterFailure = false

        storePath = try TestStore.seed()

        app = Process()
        app.executableURL = try BuiltApp.binary()
        app.arguments = ["--store", storePath, "--reorder-window"]
        try app.run()

        try waitForRows()
        try waitUntilFrontmost()
        slotCenters = rows.values.map { frame($0).midY }.sorted()
    }

    /// Waits for the exit, not just the signal: every test's window sits at
    /// the same screen position, and a not-yet-dead predecessor still owns
    /// that patch of screen — the next test's events would land in it and
    /// drive a list nobody is sampling.
    override func tearDown() {
        if app?.isRunning == true {
            app.terminate()
            app.waitUntilExit()
        }
    }

    // MARK: Reading the harness through the Accessibility API

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    /// Screen points, origin top-left — the same space `CGEvent` posts in.
    private func frame(_ element: AXUIElement) -> CGRect {
        var rect = CGRect.zero
        if let value = attribute(element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(value as! AXValue, .cgRect, &rect)
        }
        return rect
    }

    /// Finds the four category rows in the harness window and keeps their
    /// `AXUIElement`s. The references stay valid across reorders — each row's
    /// accessibility identity follows the category, not the slot — so they are
    /// looked up once and then only their frames are re-read.
    ///
    /// Each row is the `AXGroup` whose description `CategoryList` sets to the
    /// category's name.
    private func waitForRows() throws {
        // Generous: the first launch after a fresh build pays one-time costs
        // (signature validation among them) that put it well past a warm one.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            axApp = AXUIElementCreateApplication(app.processIdentifier)
            let windows = (attribute(axApp, kAXWindowsAttribute) as? [AXUIElement]) ?? []
            if let window = windows.first(where: {
                attribute($0, kAXTitleAttribute) as? String == "Reorder Harness"
            }) {
                var found: [String: AXUIElement] = [:]
                collectRows(under: window, into: &found)
                if found.count == startingOrder.count {
                    rows = found
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("""
            The harness window's rows never became readable. If the app \
            launched but the tree stayed empty, the runner probably lacks \
            Accessibility permission (System Settings → Privacy & Security).
            """)
    }

    /// Waits until the harness is the frontmost application.
    ///
    /// Rows turning up in the AX tree does not mean the window is receiving
    /// events yet — once, in a full-suite run, a drag posted in that gap moved
    /// nothing at all. The harness activates itself on launch, so frontmost is
    /// a readiness signal it will send; this waits for it rather than for luck.
    private func waitUntilFrontmost() throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("""
            The harness never became the frontmost application. If something \
            else is claiming the screen, these tests cannot aim events at it — \
            they need the machine to themselves while they run.
            """)
    }

    private func collectRows(under element: AXUIElement, into found: inout [String: AXUIElement]) {
        if let name = attribute(element, kAXDescriptionAttribute) as? String,
           startingOrder.contains(name),
           attribute(element, kAXRoleAttribute) as? String == kAXGroupRole {
            found[name] = element
        }
        for child in children(element) { collectRows(under: child, into: &found) }
    }

    /// One reading of every row's vertical centre.
    private func samplePositions() -> [String: CGFloat] {
        rows.mapValues { frame($0).midY }
    }

    private func order(of positions: [String: CGFloat]) -> [String] {
        positions.sorted { $0.value < $1.value }.map(\.key)
    }

    /// The visible order right now.
    private var visualOrder: [String] { order(of: samplePositions()) }

    /// True when every row but the dragged one rests on a slot centre.
    ///
    /// The one exception AX frames make to "committed layout only" is a rare
    /// single sample caught in the middle of the commit itself, where a
    /// neighbour reads a point or two off its slot. Those samples are torn,
    /// not meaningful, and this is the filter that drops them.
    private func isSettled(_ positions: [String: CGFloat], ignoring dragged: String) -> Bool {
        var unclaimed = slotCenters
        for (name, y) in positions where name != dragged {
            guard let slot = unclaimed.firstIndex(where: { abs($0 - y) < 1.5 }) else { return false }
            unclaimed.remove(at: slot)
        }
        return true
    }

    // MARK: Driving the drag

    /// Posts a drag as a real stream of HID mouse events — mouse-down on the
    /// row's grip, sixty small dragged events at ~30ms, mouse-up — sampling
    /// the rows' positions after every event, through the drop and the settle
    /// after it.
    ///
    /// Returns the sequence of distinct committed orders the drag passed
    /// through, starting order included. Every committed move appears in it —
    /// at this speed crossings land hundreds of milliseconds apart, far wider
    /// than the ~30ms sampling interval — so the chain *is* the commit
    /// history: a correct one-slot drag returns exactly two orders, and a
    /// revert would show as an order recurring after a different one.
    private func dragChain(grabbing name: String, toSlot slot: Int) -> [[String]] {
        let rowFrame = frame(rows[name]!)
        // The grip: a 12pt glyph at the row's leading edge.
        let start = CGPoint(x: rowFrame.minX + 6, y: rowFrame.midY)
        let end = CGPoint(x: start.x, y: slotCenters[slot])

        var sampled: [[String: CGFloat]] = [samplePositions()]

        post(.mouseMoved, start)
        usleep(120_000)
        post(.leftMouseDown, start)
        usleep(150_000)
        let steps = 60
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: start.x, y: start.y + (end.y - start.y) * t))
            usleep(30_000)
            sampled.append(samplePositions())
        }
        usleep(200_000)
        post(.leftMouseUp, end)
        // Keep sampling through the settle: a revert on drop would land here.
        for _ in 0..<20 {
            usleep(30_000)
            sampled.append(samplePositions())
        }

        return chain(from: sampled, dragged: name)
    }

    /// A press on the grip that never travels: mouse-down, the same point
    /// re-reported a few times the way trembling hardware would, mouse-up.
    /// Returns the committed-order chain, which should be just the start.
    private func pressChain(on name: String) -> [[String]] {
        let rowFrame = frame(rows[name]!)
        let point = CGPoint(x: rowFrame.minX + 6, y: rowFrame.midY)

        var sampled: [[String: CGFloat]] = [samplePositions()]

        post(.mouseMoved, point)
        usleep(120_000)
        post(.leftMouseDown, point)
        for _ in 0..<10 {
            post(.leftMouseDragged, point)
            usleep(30_000)
            sampled.append(samplePositions())
        }
        post(.leftMouseUp, point)
        for _ in 0..<10 {
            usleep(30_000)
            sampled.append(samplePositions())
        }

        return chain(from: sampled, dragged: name)
    }

    /// Collapses raw samples to the sequence of distinct committed orders:
    /// torn samples dropped, consecutive duplicates merged.
    private func chain(from sampled: [[String: CGFloat]], dragged: String) -> [[String]] {
        var result: [[String]] = []
        for positions in sampled where isSettled(positions, ignoring: dragged) {
            let current = order(of: positions)
            if current != result.last { result.append(current) }
        }
        return result
    }

    private func post(_ type: CGEventType, _ point: CGPoint) {
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState),
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    // MARK: Tests

    /// One slot crossed slowly must be one committed move: grab, one
    /// transition, drop. The historical failure here was the stutter — a slow
    /// crossing committing dozens of move/revert pairs — and a chain of
    /// exactly two orders is its negation.
    func testASlowOneSlotDragCommitsExactlyOneMove() throws {
        let moved = ["Bravo", "Alpha", "Charlie", "Delta"]
        XCTAssertEqual(dragChain(grabbing: "Alpha", toSlot: 1),
                       [startingOrder, moved])
        try TestStore.expectOrder(moved, at: storePath)
    }

    /// Three slots crossed slowly must be exactly three committed moves, one
    /// per crossing, each one slot further — never a skipped slot, never an
    /// order it had already left.
    func testAMultiSlotDragCommitsOneMovePerCrossing() throws {
        let expected = [
            ["Alpha", "Bravo", "Charlie", "Delta"],
            ["Bravo", "Alpha", "Charlie", "Delta"],
            ["Bravo", "Charlie", "Alpha", "Delta"],
            ["Bravo", "Charlie", "Delta", "Alpha"],
        ]
        XCTAssertEqual(dragChain(grabbing: "Alpha", toSlot: 3), expected)
        try TestStore.expectOrder(expected.last!, at: storePath)
    }

    /// A press that never travels must commit nothing — the gesture's minimum
    /// distance exists for exactly this — and must leave the store exactly as
    /// seeded.
    func testAStationaryPressCommitsNothing() throws {
        XCTAssertEqual(pressChain(on: "Bravo"), [startingOrder])
        XCTAssertEqual(try TestStore.categoryOrder(at: storePath), startingOrder)
    }

    /// After a drag — upward this time — what the store holds must be what the
    /// screen shows. An order that reached the eye but not the disk would look
    /// right until the next launch.
    func testThePersistedOrderMatchesTheVisualOrder() throws {
        let expected = ["Alpha", "Delta", "Bravo", "Charlie"]
        let chain = dragChain(grabbing: "Delta", toSlot: 1)
        XCTAssertEqual(chain.last, expected)
        try TestStore.expectOrder(expected, at: storePath)
        XCTAssertEqual(visualOrder, try TestStore.categoryOrder(at: storePath))
    }
}
