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
