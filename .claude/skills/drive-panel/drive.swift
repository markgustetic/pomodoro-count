import AppKit
import ApplicationServices

// Headless driver for the reorder investigation.
// Usage: swift drive.swift <pid> <command>
//   tree                 — dump the AX tree (roles, titles, frames)
//   open                 — click the status item so the panel opens
//   settings             — click the Settings button in the open panel
//   drag <from> <to>     — slow-drag row <from>'s grip to row <to>'s centre,
//                          sampling every row's Y position along the way
//   rows                 — print each category row's frame
//   advance <row>        — read the session-target pill, click row <row> to meet
//                          its goal, read the pill again, without reopening
//   counter <row>        — open row <row>'s count popover and work its − and +
//   counterkeys <row>    — same popover, short VoiceOver-and-Escape probe only
//   countershot <row> <path> — open row <row>'s popover and screenshot it in place
//   settingsshot <button> <path> — open Settings, click <button>, and screenshot

let pid = pid_t(CommandLine.arguments[1])!
let command = CommandLine.arguments[2]
let app = AXUIElementCreateApplication(pid)

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(el, name as CFString, &value)
    return value
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func str(_ el: AXUIElement, _ name: String) -> String {
    (attr(el, name) as? String) ?? ""
}

func frame(_ el: AXUIElement) -> CGRect {
    var rect = CGRect.zero
    if let posValue = attr(el, kAXPositionAttribute) {
        AXValueGetValue(posValue as! AXValue, .cgPoint, &rect.origin)
    }
    if let sizeValue = attr(el, kAXSizeAttribute) {
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &rect.size)
    }
    return rect
}

func dump(_ el: AXUIElement, depth: Int, maxDepth: Int = 12) {
    guard depth <= maxDepth else { return }
    let f = frame(el)
    let role = str(el, kAXRoleAttribute)
    let title = str(el, kAXTitleAttribute)
    let desc = str(el, kAXDescriptionAttribute)
    let value = (attr(el, kAXValueAttribute) as? String) ?? ""
    let pad = String(repeating: "  ", count: depth)
    print("\(pad)\(role) title='\(title)' desc='\(desc)' value='\(value)' frame=(\(Int(f.origin.x)),\(Int(f.origin.y)) \(Int(f.width))x\(Int(f.height)))")
    for c in children(el) { dump(c, depth: depth + 1, maxDepth: maxDepth) }
}

/// Depth-first search for the first element matching.
func find(_ el: AXUIElement, depth: Int = 0, where match: (AXUIElement) -> Bool) -> AXUIElement? {
    guard depth < 25 else { return nil }
    if match(el) { return el }
    for c in children(el) {
        if let hit = find(c, depth: depth + 1, where: match) { return hit }
    }
    return nil
}

func findAll(_ el: AXUIElement, depth: Int = 0, into out: inout [AXUIElement], where match: (AXUIElement) -> Bool) {
    guard depth < 25 else { return }
    if match(el) { out.append(el) }
    for c in children(el) {
        findAll(c, depth: depth + 1, into: &out, where: match)
    }
}

let source = CGEventSource(stateID: .hidSystemState)
var lastPoint = CGPoint.zero

func post(_ type: CGEventType, _ point: CGPoint) {
    let e = CGEvent(mouseEventSource: source, mouseType: type,
                    mouseCursorPosition: point, mouseButton: .left)
    // Real mouse streams carry a click state on every event of the drag, and
    // dragged events carry deltas; synthetic streams default both to zero.
    if type == .leftMouseDown || type == .leftMouseDragged || type == .leftMouseUp {
        e?.setIntegerValueField(.mouseEventClickState, value: 1)
    }
    if type == .leftMouseDragged || type == .mouseMoved {
        e?.setDoubleValueField(.mouseEventDeltaX, value: Double(point.x - lastPoint.x))
        e?.setDoubleValueField(.mouseEventDeltaY, value: Double(point.y - lastPoint.y))
    }
    lastPoint = point
    e?.post(tap: .cghidEventTap)
}

func click(_ point: CGPoint) {
    post(.mouseMoved, point)
    usleep(150_000)
    post(.leftMouseDown, point)
    usleep(80_000)
    post(.leftMouseUp, point)
    usleep(150_000)
}

/// Every top-level AX element the app offers: windows plus the menu-bar extra.
func roots() -> [AXUIElement] {
    var out: [AXUIElement] = []
    if let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement] { out += windows }
    if let extras = attr(app, "AXExtrasMenuBar") { out.append(extras as! AXUIElement) }
    for name in ["AXMainWindow", "AXFocusedWindow"] {
        if let w = attr(app, name) { out.append(w as! AXUIElement) }
    }
    return out
}

func categoryRows() -> [(String, CGRect)] {
    var rows: [AXUIElement] = []
    for root in roots() {
        findAll(root, into: &rows) { el in
            let t = str(el, kAXTitleAttribute)
            let d = str(el, kAXDescriptionAttribute)
            return ["Alpha", "Bravo", "Charlie", "Delta"].contains(t)
                || ["Alpha", "Bravo", "Charlie", "Delta"].contains(d)
        }
    }
    return rows.map { el in
        (str(el, kAXTitleAttribute) + str(el, kAXDescriptionAttribute), frame(el))
    }
}

switch command {
case "tree":
    for root in roots() { dump(root, depth: 0) }

case "open":
    guard let extras = attr(app, "AXExtrasMenuBar") else {
        print("no AXExtrasMenuBar"); exit(1)
    }
    let items = children(extras as! AXUIElement)
    guard let item = items.first else { print("no status item"); exit(1) }
    let f = frame(item)
    print("status item at \(f)")
    click(CGPoint(x: f.midX, y: f.midY))
    usleep(600_000)
    print("windows now:", (attr(app, kAXWindowsAttribute) as? [AXUIElement])?.count ?? 0)

case "settings":
    var buttons: [AXUIElement] = []
    for root in roots() {
        findAll(root, into: &buttons) { el in
            str(el, kAXRoleAttribute) == kAXButtonRole as String
                && (str(el, kAXTitleAttribute) == "Settings" || str(el, kAXDescriptionAttribute) == "Settings")
        }
    }
    guard let settings = buttons.first else { print("no Settings button"); exit(1) }
    let f = frame(settings)
    print("settings button at \(f)")
    click(CGPoint(x: f.midX, y: f.midY))

case "button":
    let name = CommandLine.arguments[3]
    var buttons: [AXUIElement] = []
    for root in roots() {
        findAll(root, into: &buttons) { el in
            str(el, kAXRoleAttribute) == kAXButtonRole as String
                && (str(el, kAXTitleAttribute) == name || str(el, kAXDescriptionAttribute) == name)
        }
    }
    guard let target = buttons.first else { print("no button '\(name)'"); exit(1) }
    let f = frame(target)
    print("clicking '\(name)' at \(f)")
    click(CGPoint(x: f.midX, y: f.midY))

case "texts":
    var texts: [AXUIElement] = []
    for root in roots() {
        findAll(root, into: &texts) { el in
            str(el, kAXRoleAttribute) == kAXStaticTextRole as String
        }
    }
    for t in texts {
        let value = (attr(t, kAXValueAttribute) as? String) ?? str(t, kAXTitleAttribute)
        if !value.isEmpty { print(value) }
    }

case "statusitem":
    guard let extras = attr(app, "AXExtrasMenuBar") else { print("no AXExtrasMenuBar"); exit(1) }
    for item in children(extras as! AXUIElement) {
        print(str(item, kAXTitleAttribute))
    }

case "measuretabs":
    // Open the panel and record its window height on each tab, in one
    // process so the panel cannot dismiss between steps.
    guard let extras = attr(app, "AXExtrasMenuBar") else { print("no AXExtrasMenuBar"); exit(1) }
    guard let item = children(extras as! AXUIElement).first else { print("no status item"); exit(1) }
    let itemFrame = frame(item)
    click(CGPoint(x: itemFrame.midX, y: itemFrame.midY))
    usleep(1_200_000)

    func panelHeight() -> CGFloat {
        guard let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement],
              let panel = windows.first else { return -1 }
        return frame(panel).height
    }
    func clickButton(_ name: String) {
        var buttons: [AXUIElement] = []
        for root in roots() {
            findAll(root, into: &buttons) { el in
                str(el, kAXRoleAttribute) == kAXButtonRole as String
                    && (str(el, kAXTitleAttribute) == name || str(el, kAXDescriptionAttribute) == name)
            }
        }
        if let b = buttons.first {
            let f = frame(b)
            click(CGPoint(x: f.midX, y: f.midY))
        } else {
            print("no button '\(name)'")
        }
        usleep(1_200_000)
    }

    print("focus tab: \(panelHeight())")
    clickButton("Settings")
    print("settings tab: \(panelHeight())")
    clickButton("History")
    print("history tab: \(panelHeight())")
    clickButton("Focus")
    print("focus again: \(panelHeight())")

case "openclick":
    // Open the panel and click a button in one process, so the panel has no
    // gap in which to dismiss.
    let name = CommandLine.arguments[3]
    guard let extras = attr(app, "AXExtrasMenuBar") else { print("no AXExtrasMenuBar"); exit(1) }
    guard let item = children(extras as! AXUIElement).first else { print("no status item"); exit(1) }
    let itemFrame = frame(item)
    click(CGPoint(x: itemFrame.midX, y: itemFrame.midY))
    usleep(1_500_000)
    var buttons: [AXUIElement] = []
    for root in roots() {
        findAll(root, into: &buttons) { el in
            str(el, kAXRoleAttribute) == kAXButtonRole as String
                && (str(el, kAXTitleAttribute) == name || str(el, kAXDescriptionAttribute) == name)
        }
    }
    guard let target = buttons.first else { print("no button '\(name)'"); exit(1) }
    let bf = frame(target)
    click(CGPoint(x: bf.midX, y: bf.midY))
    print("clicked '\(name)'")

case "advance":
    // Open the panel, read the session-target pill, click a category row to
    // log the pomodoro that meets its goal, then read the pill again — all in
    // one process. The claim under test is that the pill changes *without the
    // panel being reopened*, and a two-invocation version could not tell a
    // live update from a fresh render of a value that changed while it was shut.
    let rowName = CommandLine.arguments[3]
    guard let extras = attr(app, "AXExtrasMenuBar") else { print("no AXExtrasMenuBar"); exit(1) }
    guard let item = children(extras as! AXUIElement).first else { print("no status item"); exit(1) }
    let itemFrame = frame(item)
    click(CGPoint(x: itemFrame.midX, y: itemFrame.midY))
    usleep(1_500_000)

    // The pill is a Menu carrying accessibilityLabel "Session target"; the
    // category it names is its accessibilityValue, so this reads the promise
    // the panel is making rather than pixels (see rule 5).
    func pillValue() -> String {
        for root in roots() {
            if let pill = find(root, where: { el in
                str(el, kAXTitleAttribute) == "Session target"
                    || str(el, kAXDescriptionAttribute) == "Session target"
            }) {
                return (attr(pill, kAXValueAttribute) as? String) ?? "<no value>"
            }
        }
        return "<pill not found>"
    }

    print("pill before: \(pillValue())")

    var rowEls: [AXUIElement] = []
    for root in roots() {
        findAll(root, into: &rowEls) { el in
            str(el, kAXTitleAttribute) == rowName || str(el, kAXDescriptionAttribute) == rowName
        }
    }
    // A category's name also labels its Settings text field, so prefer the
    // element whose value is a progress string — that one is the Focus row.
    let row = rowEls.first {
        ((attr($0, kAXValueAttribute) as? String) ?? "").contains("pomodoro")
    } ?? rowEls.first { frame($0).height > 0 }
    guard let row else { print("no row '\(rowName)' (matched \(rowEls.count) elements)"); exit(1) }

    let rf = frame(row)
    print("clicking row '\(rowName)' value='\((attr(row, kAXValueAttribute) as? String) ?? "")'")
    click(CGPoint(x: rf.midX, y: rf.midY))
    usleep(1_200_000)
    print("pill after:  \(pillValue())")
    print("row after:   '\((attr(row, kAXValueAttribute) as? String) ?? "")'")

case "counter":
    // Open the panel, tap a category row to raise its count popover, then work
    // the popover's − and + in the same process.
    //
    // The claim under test is the one neither the unit suite nor `--preview`
    // can reach: that a popover presents *at all* from inside the
    // non-activating NSPanel — the panel dismisses when it loses key status,
    // which is what rules alerts out — and that its buttons commit while it
    // stays up. Re-queried before every click, because each tap rebuilds the
    // popover's content and stales the previous element reference.
    let rowName = CommandLine.arguments[3]
    guard let extras = attr(app, "AXExtrasMenuBar") else { print("no AXExtrasMenuBar"); exit(1) }
    guard let item = children(extras as! AXUIElement).first else { print("no status item"); exit(1) }
    let itemFrame = frame(item)
    click(CGPoint(x: itemFrame.midX, y: itemFrame.midY))
    usleep(1_500_000)

    // The panel's right edge, read now while it is still the only AX window —
    // once the popover opens there are two, and nothing at that point says
    // which is which. `popoverCount()` below uses this instead of a coordinate
    // from one particular display, which only ever worked on the display it
    // was measured against and returned silently empty everywhere else.
    let panelMaxX = (attr(app, kAXWindowsAttribute) as? [AXUIElement])?.first.map { frame($0).maxX } ?? 0

    // A category's name also labels its Settings text field. `advance` picks the
    // Focus row by requiring a progress string in the value; that is deliberately
    // NOT the rule here, because whether the row still exposes a value is one of
    // the things under test. Fall back to the widest match inside a scroll area.
    func focusRow() -> AXUIElement? {
        var els: [AXUIElement] = []
        for root in roots() {
            findAll(root, into: &els) { el in
                str(el, kAXTitleAttribute) == rowName || str(el, kAXDescriptionAttribute) == rowName
            }
        }
        return els.first { ((attr($0, kAXValueAttribute) as? String) ?? "").contains("pomodoro") }
            ?? els.max { frame($0).width < frame($1).width }
    }

    func rowValue() -> String {
        guard let row = focusRow() else { return "<row gone>" }
        let role = str(row, kAXRoleAttribute)
        let value = (attr(row, kAXValueAttribute) as? String) ?? ""
        // The action names are the only honest test of an
        // `accessibilityAdjustableAction`: it is meant to give VoiceOver a
        // swipe-up/down on the row, which shows up here as AXIncrement and
        // AXDecrement. Reading only role and value would let a silently
        // unreachable action pass as working.
        var names: CFArray?
        AXUIElementCopyActionNames(row, &names)
        let actions = (names as? [String]) ?? []
        return "role=\(role) value='\(value)' actions=\(actions)"
    }

    func stepper(_ label: String) -> (enabled: Bool, frame: CGRect)? {
        var els: [AXUIElement] = []
        for root in roots() {
            findAll(root, into: &els) { el in
                // `hasPrefix`, not `==`: the accessibility labels now carry the
                // category name too ("Remove one pomodoro from Alpha"), and this
                // helper is called with just the fixed lead-in.
                str(el, kAXRoleAttribute) == kAXButtonRole as String
                    && (str(el, kAXTitleAttribute).hasPrefix(label) || str(el, kAXDescriptionAttribute).hasPrefix(label))
            }
        }
        guard let el = els.first else { return nil }
        return ((attr(el, kAXEnabledAttribute) as? NSNumber)?.boolValue ?? true, frame(el))
    }

    func describe(_ s: (enabled: Bool, frame: CGRect)?) -> String {
        guard let s else { return "ABSENT" }
        return "enabled=\(s.enabled) at (\(Int(s.frame.midX)),\(Int(s.frame.midY)))"
    }

    func report(_ stage: String) {
        print("[\(stage)]")
        print("    row:   \(rowValue())")
        print("    minus: \(describe(stepper("Remove one pomodoro")))")
        print("    plus:  \(describe(stepper("Add one pomodoro")))")
    }

    func tap(_ label: String, _ stage: String) {
        guard let s = stepper(label), s.enabled else {
            print("[\(stage)] SKIPPED — '\(label)' \(stepper(label) == nil ? "absent" : "disabled")")
            return
        }
        click(CGPoint(x: s.frame.midX, y: s.frame.midY))
        usleep(900_000)
        report(stage)
    }

    report("panel open, before row tap")
    guard let row = focusRow() else { print("no row '\(rowName)'"); exit(1) }
    let rf = frame(row)
    print("row frame: (\(Int(rf.origin.x)),\(Int(rf.origin.y))) \(Int(rf.width))x\(Int(rf.height))")
    click(CGPoint(x: rf.midX, y: rf.midY))
    usleep(1_400_000)
    report("after row tap")

    // A popover is its own window, so it should appear here as a second entry.
    let wins = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    print("AX windows now: \(wins.count)")
    for w in wins {
        print("    role=\(str(w, kAXRoleAttribute)) subrole=\(str(w, kAXSubroleAttribute)) frame=\(frame(w))")
    }

    // The popover's count carries `progress.accessibilityValue` as its label,
    // so this reads the number the popover is actually promising, not pixels.
    //
    // Read out of AXValue, not AXDescription. A `Text`'s accessibility label
    // lands in the AXValue of its AXStaticText element — an AXStaticText's
    // "value" *is* its string — so the AXDescription this used to match on was
    // always empty, and the readout printed '' at every step while looking like
    // a missing label. That is the same wrong-attribute mistake that made the
    // category rows look like they exposed no value at all; see SKILL.md.
    func popoverText(_ el: AXUIElement) -> String {
        let value = (attr(el, kAXValueAttribute) as? String) ?? ""
        return value.isEmpty ? str(el, kAXDescriptionAttribute) : value
    }

    func popoverCount() -> String {
        var texts: [AXUIElement] = []
        for root in roots() {
            findAll(root, into: &texts) { el in
                str(el, kAXRoleAttribute) == kAXStaticTextRole as String
                    && popoverText(el).contains("pomodoro")
                    && frame(el).midX > panelMaxX   // inside the popover, not the panel
            }
        }
        // `roots()` hands back the same window more than once — it collects
        // AXWindows *and* AXMainWindow *and* AXFocusedWindow — so a single
        // element is found once per root that reaches it. Without this the one
        // count text reads out as "0 of 1 pomodoros | 0 of 1 pomodoros", which
        // looks like a duplicated label in the popover rather than a duplicated
        // walk. Deduped on element identity, not on the string, so two texts
        // that genuinely agree would still both show.
        var unique: [AXUIElement] = []
        for t in texts where !unique.contains(where: { CFEqual($0, t) }) { unique.append(t) }
        return unique.map(popoverText).joined(separator: " | ")
    }

    print("popover count readout: '\(popoverCount())'")

    tap("Add one pomodoro", "after + (1st)")
    print("    count readout: '\(popoverCount())'")
    tap("Add one pomodoro", "after + (2nd)")
    print("    count readout: '\(popoverCount())'")
    tap("Remove one pomodoro", "after - (1st)")
    print("    count readout: '\(popoverCount())'")
    tap("Remove one pomodoro", "after - (2nd)")
    print("    count readout: '\(popoverCount())'")
    tap("Remove one pomodoro", "after - (3rd, expect count 0)")
    report("after three - taps — minus should be disabled at zero")

    // The VoiceOver path, exercised as VoiceOver would: perform the AX actions
    // rather than clicking. Proves the adjustable action is wired to something,
    // not merely advertised.
    if let row = focusRow() {
        AXUIElementPerformAction(row, "AXIncrement" as CFString)
        usleep(900_000)
        print("[after AXIncrement] count readout: '\(popoverCount())' \(rowValue())")
        AXUIElementPerformAction(row, "AXDecrement" as CFString)
        usleep(900_000)
        print("[after AXDecrement] count readout: '\(popoverCount())' \(rowValue())")
    }

    // Escape must close the popover and leave the panel standing.
    if let esc = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true) {
        esc.post(tap: .cghidEventTap)
    }
    if let escUp = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) {
        escUp.post(tap: .cghidEventTap)
    }
    usleep(1_000_000)
    report("after Escape — steppers should be ABSENT, row still present")

case "settingsshot":
    // Open the panel, go to Settings, click a named button, screenshot. Exists to
    // compare a PRE-EXISTING popover's appearance against a new one under the
    // same theme — "the new popover looks wrong" and "every popover in this app
    // looks like that" call for different fixes, and only a side-by-side tells
    // them apart.
    let btnName = CommandLine.arguments[3]
    let outFile = CommandLine.arguments[4]
    guard let extras = attr(app, "AXExtrasMenuBar") else { print("no AXExtrasMenuBar"); exit(1) }
    guard let item = children(extras as! AXUIElement).first else { print("no status item"); exit(1) }
    click(CGPoint(x: frame(item).midX, y: frame(item).midY))
    usleep(1_500_000)

    func namedButton(_ name: String) -> AXUIElement? {
        var els: [AXUIElement] = []
        for root in roots() {
            findAll(root, into: &els) { el in
                str(el, kAXRoleAttribute) == kAXButtonRole as String
                    && (str(el, kAXTitleAttribute) == name || str(el, kAXDescriptionAttribute) == name)
            }
        }
        return els.first
    }

    guard let settingsBtn = namedButton("Settings") else { print("no Settings button"); exit(1) }
    click(CGPoint(x: frame(settingsBtn).midX, y: frame(settingsBtn).midY))
    usleep(1_400_000)
    guard let target = namedButton(btnName) else { print("no button '\(btnName)'"); exit(1) }
    click(CGPoint(x: frame(target).midX, y: frame(target).midY))
    usleep(1_500_000)

    var shotBox = CGRect.null
    for w in (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { shotBox = shotBox.union(frame(w)) }
    shotBox = shotBox.insetBy(dx: -40, dy: -40)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-R\(Int(shotBox.minX)),\(Int(shotBox.minY)),\(Int(shotBox.width)),\(Int(shotBox.height))", outFile]
    try? p.run()
    p.waitUntilExit()
    print("screencapture exit \(p.terminationStatus) -> \(outFile)")

case "countershot":
    // Open the panel, raise a row's count popover, and screenshot it from
    // INSIDE this process. A popover is its own window and the panel dismisses
    // when it loses key status, so a separate `screencapture` invocation would
    // photograph an already-closed popover. This is the only way to see the
    // thing `--preview` structurally cannot render.
    let rowName = CommandLine.arguments[3]
    let outPath = CommandLine.arguments[4]
    guard let extras = attr(app, "AXExtrasMenuBar") else { print("no AXExtrasMenuBar"); exit(1) }
    guard let item = children(extras as! AXUIElement).first else { print("no status item"); exit(1) }
    click(CGPoint(x: frame(item).midX, y: frame(item).midY))
    usleep(1_500_000)

    var rowEls: [AXUIElement] = []
    for root in roots() {
        findAll(root, into: &rowEls) { el in
            str(el, kAXTitleAttribute) == rowName || str(el, kAXDescriptionAttribute) == rowName
        }
    }
    guard let shotRow = rowEls.max(by: { frame($0).width < frame($1).width })
    else { print("no row '\(rowName)'"); exit(1) }
    click(CGPoint(x: frame(shotRow).midX, y: frame(shotRow).midY))
    usleep(1_400_000)

    // Union of the panel window and the popover's buttons, so the capture holds
    // both and the popover's placement relative to the row is visible.
    var box = CGRect.null
    for w in (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
        box = box.union(frame(w))
    }
    var stepEls: [AXUIElement] = []
    for root in roots() {
        findAll(root, into: &stepEls) { el in
            // `hasPrefix`, not exact match — see the same note in `stepper` in
            // the `counter` case: the label now carries the category name too.
            let combined = str(el, kAXTitleAttribute) + str(el, kAXDescriptionAttribute)
            return str(el, kAXRoleAttribute) == kAXButtonRole as String
                && ["Remove one pomodoro", "Add one pomodoro"].contains { combined.hasPrefix($0) }
        }
    }
    guard !stepEls.isEmpty else { print("popover never opened — nothing to shoot"); exit(1) }
    for el in stepEls { box = box.union(frame(el)) }
    box = box.insetBy(dx: -24, dy: -24)
    print("capturing \(Int(box.width))x\(Int(box.height)) at (\(Int(box.minX)),\(Int(box.minY)))")

    let shot = Process()
    shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    shot.arguments = ["-x", "-R\(Int(box.minX)),\(Int(box.minY)),\(Int(box.width)),\(Int(box.height))", outPath]
    try? shot.run()
    shot.waitUntilExit()
    print("screencapture exit \(shot.terminationStatus) -> \(outPath)")

case "counterkeys":
    // The VoiceOver path and Escape dismissal, in a DELIBERATELY SHORT sequence.
    // `counter`'s full click run takes ~12s of posted events, and the panel has
    // been observed dismissing on its own before the end of it — long sequences
    // cannot distinguish "Escape closed the popover" from "the panel had already
    // gone". So this does the minimum: open, tap the row, and probe.
    let rowName = CommandLine.arguments[3]
    guard let extras = attr(app, "AXExtrasMenuBar") else { print("no AXExtrasMenuBar"); exit(1) }
    guard let item = children(extras as! AXUIElement).first else { print("no status item"); exit(1) }
    click(CGPoint(x: frame(item).midX, y: frame(item).midY))
    usleep(1_500_000)

    func row2() -> AXUIElement? {
        var els: [AXUIElement] = []
        for root in roots() {
            findAll(root, into: &els) { el in
                str(el, kAXTitleAttribute) == rowName || str(el, kAXDescriptionAttribute) == rowName
            }
        }
        return els.max { frame($0).width < frame($1).width }
    }

    func steppersPresent() -> String {
        var els: [AXUIElement] = []
        for root in roots() {
            findAll(root, into: &els) { el in
                // `hasPrefix`, not exact match — see the same note in `stepper`
                // in the `counter` case: the label now carries the category name.
                let combined = str(el, kAXTitleAttribute) + str(el, kAXDescriptionAttribute)
                return str(el, kAXRoleAttribute) == kAXButtonRole as String
                    && ["Remove one pomodoro", "Add one pomodoro"].contains { combined.hasPrefix($0) }
            }
        }
        return els.isEmpty ? "ABSENT" : "PRESENT (\(els.count))"
    }

    guard let r = row2() else { print("no row '\(rowName)'"); exit(1) }
    print("steppers before row tap: \(steppersPresent())")

    // AXIncrement with the popover still CLOSED — the adjustable action is on
    // the row itself, and the point of it is that VoiceOver never needs the
    // popover at all.
    AXUIElementPerformAction(r, "AXIncrement" as CFString)
    usleep(1_000_000)
    print("after AXIncrement (popover never opened): steppers \(steppersPresent())")
    AXUIElementPerformAction(r, "AXIncrement" as CFString)
    usleep(1_000_000)
    AXUIElementPerformAction(r, "AXDecrement" as CFString)
    usleep(1_000_000)
    print("performed +2 then -1 via AX actions; check the store for a net +1")

    click(CGPoint(x: frame(r).midX, y: frame(r).midY))
    usleep(1_400_000)
    print("steppers after row tap: \(steppersPresent())")

    if let esc = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true) {
        esc.post(tap: .cghidEventTap)
    }
    if let escUp = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) {
        escUp.post(tap: .cghidEventTap)
    }
    usleep(1_200_000)
    print("steppers after Escape: \(steppersPresent())")
    print("panel still up? row \(row2() == nil ? "GONE — panel dismissed too" : "still present")")

case "window":
    // The app's window frames, from AX and from the window server. Compare
    // them: AX-reported ELEMENT frames can lie outside the actual window
    // (content laid out below a collapsed frame is still "positioned").
    if let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement] {
        for w in windows { print("AX window:", frame(w)) }
    }
    if let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] {
        for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == pid {
            print("CG window:", w[kCGWindowBounds as String] as? [String: Any] ?? [:],
                  "onscreen:", (w[kCGWindowIsOnscreen as String] as? Bool) ?? false)
        }
    }

case "rows":
    for (name, f) in categoryRows() {
        print("\(name): (\(Int(f.origin.x)),\(Int(f.origin.y))) \(Int(f.width))x\(Int(f.height))")
    }

case "drag":
    let fromName = CommandLine.arguments[3]
    let toName = CommandLine.arguments[4]
    let rows = categoryRows()
    guard let from = rows.first(where: { $0.0 == fromName })?.1,
          let to = rows.first(where: { $0.0 == toName })?.1 else {
        print("rows not found among:", rows.map(\.0)); exit(1)
    }
    // The grip: 12pt glyph at the row's leading edge (6pt in), vertically centred.
    let start = CGPoint(x: from.minX + 6, y: from.midY)
    let end = CGPoint(x: from.minX + 6, y: to.midY)
    print("drag \(start) -> \(end)")

    post(.mouseMoved, start)
    usleep(200_000)
    post(.leftMouseDown, start)
    usleep(200_000)
    let steps = 60
    for step in 1...steps {
        let t = CGFloat(step) / CGFloat(steps)
        let p = CGPoint(x: start.x, y: start.y + (end.y - start.y) * t)
        post(.leftMouseDragged, p)
        usleep(30_000)
        if step % 6 == 0 {
            let sampled = categoryRows()
                .sorted { $0.1.origin.y < $1.1.origin.y }
                .map { "\($0.0)@\(Int($0.1.origin.y))" }
                .joined(separator: " ")
            print("step \(step) pointerY=\(Int(p.y)) rows: \(sampled)")
        }
    }
    usleep(200_000)
    post(.leftMouseUp, end)
    usleep(300_000)
    let final = categoryRows()
        .sorted { $0.1.origin.y < $1.1.origin.y }
        .map(\.0)
    print("final visual order:", final.joined(separator: ", "))

default:
    print("unknown command")
}
