# Category Reordering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user drag a grip handle on each Settings category row to
reorder categories, which reorders them in the Focus panel too.

**Architecture:** Three pieces. `Reorder.destination` is pure arithmetic over
numbers — given a drag's starting index and how far it has travelled, which slot
does the row belong in — with no SwiftUI, so it is unit-tested directly.
`AppModel.moveCategory(from:to:)` performs the mutation and absorbs the
`Array.move(fromOffsets:toOffset:)` insertion-offset off-by-one. A `DragGesture`
on the grip wires the two together. The `List` that carries `.onMove` today is
replaced by a plain `VStack` whose row height is measured at layout time.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit (`NSCursor`), swift-testing.

## Global Constraints

- **Deployment target is macOS 14.** `onGeometryChange` (macOS 15) is not
  available; the row height is measured with `GeometryReader` plus `.task(id:)`.
- **Panel width is 300pt.** The grip must stay narrow — 12pt glyph, 6pt spacing.
- **Test command is `just test`**, which borrows Xcode's toolchain. Plain
  `swift test` fails on a Command Line Tools-only machine.
- **Commit and push after every task**, then run `just install` so the running
  app in `/Applications` matches the commit.
- **The fallback bucket is not reorderable.** It stays in its own Settings
  section and stays last in `todayProgress`. No task touches that.
- **Comments explain why, not what**, matching the surrounding code.

---

### Task 1: The drag arithmetic

Pure, no SwiftUI, no model. This is where reorder bugs live — rounding at the
midpoint between slots, running off either end — so it is tested on its own
before anything can call it.

**Files:**
- Create: `Sources/PomodoroCount/Reorder.swift`
- Test: `Tests/PomodoroCountTests/ReorderTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `Reorder.destination(from: Int, translation: CGFloat, pitch: CGFloat, count: Int) -> Int`

- [ ] **Step 1: Write the failing tests**

Create `Tests/PomodoroCountTests/ReorderTests.swift`:

```swift
import Testing
import Foundation
@testable import PomodoroCount

/// The drag arithmetic, tested without a UI. `pitch` is 32 throughout — one
/// row's height plus the gap to the next — so a translation of 32 is exactly
/// one slot and 16 is exactly the boundary between two.
@Suite struct ReorderTests {

    private let pitch: CGFloat = 32

    @Test func noMovementStaysPut() {
        #expect(Reorder.destination(from: 2, translation: 0, pitch: pitch, count: 5) == 2)
    }

    @Test func draggingDownMovesOneSlotPerRow() {
        #expect(Reorder.destination(from: 0, translation: 32, pitch: pitch, count: 5) == 1)
        #expect(Reorder.destination(from: 0, translation: 96, pitch: pitch, count: 5) == 3)
    }

    @Test func draggingUpMovesOneSlotPerRow() {
        #expect(Reorder.destination(from: 4, translation: -32, pitch: pitch, count: 5) == 3)
        #expect(Reorder.destination(from: 4, translation: -96, pitch: pitch, count: 5) == 1)
    }

    /// Short of half a row is still the same slot: the row commits a move only
    /// once it has travelled far enough to have changed places with a neighbour.
    @Test func lessThanHalfARowDoesNotMove() {
        #expect(Reorder.destination(from: 1, translation: 15, pitch: pitch, count: 5) == 1)
        #expect(Reorder.destination(from: 1, translation: -15, pitch: pitch, count: 5) == 1)
    }

    /// The boundary, pinned deliberately rather than left to whatever rounding
    /// happens to do: exactly half a row commits the move, in both directions.
    @Test func exactlyHalfARowCommitsTheMove() {
        #expect(Reorder.destination(from: 1, translation: 16, pitch: pitch, count: 5) == 2)
        #expect(Reorder.destination(from: 1, translation: -16, pitch: pitch, count: 5) == 0)
    }

    @Test func draggingPastTheTopClampsToTheFirstSlot() {
        #expect(Reorder.destination(from: 1, translation: -500, pitch: pitch, count: 5) == 0)
    }

    @Test func draggingPastTheBottomClampsToTheLastSlot() {
        #expect(Reorder.destination(from: 1, translation: 500, pitch: pitch, count: 5) == 4)
    }

    /// Rows report their height at layout time, so pitch is zero until the first
    /// layout has run. A drag in that window must not be able to reorder.
    @Test func anUnmeasuredPitchNeverMoves() {
        #expect(Reorder.destination(from: 2, translation: 200, pitch: 0, count: 5) == 2)
        #expect(Reorder.destination(from: 2, translation: 200, pitch: -8, count: 5) == 2)
    }

    @Test func anEmptyListNeverMoves() {
        #expect(Reorder.destination(from: 0, translation: 200, pitch: pitch, count: 0) == 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
just test
```

Expected: compile failure — `cannot find 'Reorder' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/PomodoroCount/Reorder.swift`:

```swift
import Foundation

/// The arithmetic behind drag-to-reorder, deliberately free of SwiftUI so it can
/// be tested directly. Reordering goes wrong in exactly two places — rounding at
/// the midpoint between two slots, and running off either end of the list — so
/// both live in one function over plain numbers rather than a few lines buried
/// inside a gesture.
enum Reorder {

    /// The slot a dragged row now belongs in.
    ///
    /// - Parameters:
    ///   - startIndex: the index the drag was picked up from.
    ///   - translation: how far the pointer has moved vertically since, in
    ///     points, positive downward — i.e. `DragGesture.Value.translation.height`.
    ///   - pitch: the distance from one row's top edge to the next: row height
    ///     plus the spacing between rows.
    ///   - count: how many rows there are.
    ///
    /// Half a pitch is the boundary. `rounded()` rounds half away from zero, so
    /// dragging down exactly half a row moves down one slot and dragging up
    /// exactly half a row moves up one.
    ///
    /// Returns `startIndex` unchanged when `pitch` is not positive or the list is
    /// empty: a row whose height has not been measured yet must not be able to
    /// produce a move.
    static func destination(from startIndex: Int,
                            translation: CGFloat,
                            pitch: CGFloat,
                            count: Int) -> Int {
        guard pitch > 0, count > 0 else { return startIndex }
        let slots = Int((translation / pitch).rounded())
        return min(max(startIndex + slots, 0), count - 1)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
just test
```

Expected: all tests pass, including the 195 that already existed.

- [ ] **Step 5: Commit and push**

```bash
git add Sources/PomodoroCount/Reorder.swift Tests/PomodoroCountTests/ReorderTests.swift
git commit -m "Work out which slot a dragged row lands in"
git push origin main
```

---

### Task 2: `AppModel.moveCategory(from:to:)`

The mutation, with the off-by-one absorbed once. Added alongside the existing
`moveCategories(fromOffsets:toOffset:)`, which still has a caller until Task 4
removes it.

**Files:**
- Modify: `Sources/PomodoroCount/AppModel+Categories.swift:178-180` (add below
  the existing `moveCategories`)
- Test: `Tests/PomodoroCountTests/CategoryManagementTests.swift` (the
  `// MARK: Reordering` section, around line 168)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `AppModel.moveCategory(from: Int, to: Int)` and
  `AppModel.nudgeCategory(id: UUID, by: Int)`, both `@MainActor`, both returning
  `Void`.

- [ ] **Step 1: Write the failing tests**

In `Tests/PomodoroCountTests/CategoryManagementTests.swift`, find the
`// MARK: Reordering` section. Leave the existing `reorderingChangesDisplayOrder`
test alone — Task 4 removes it with the method it covers. Add below it:

```swift
    /// Three categories, so a move can be tested as something other than a swap
    /// of two — the direction-dependent off-by-one only shows up with three.
    private func threeCategories() -> AppModel {
        let m = configured()
        m.addCategory(name: "Admin", dailyGoal: 2)
        return m       // Work, Music, Admin
    }

    @Test func movingACategoryDownLandsInTheTargetSlot() {
        let m = threeCategories()
        m.moveCategory(from: 0, to: 2)
        #expect(m.settings.categories.map(\.name) == ["Music", "Admin", "Work"])
    }

    /// The `toOffset` off-by-one, pinned: `move(fromOffsets:toOffset:)` measures
    /// its offset before the removal, so passing the destination unadjusted here
    /// would leave the order untouched and the row would look stuck.
    @Test func movingACategoryDownByOneActuallyMovesIt() {
        let m = threeCategories()
        m.moveCategory(from: 0, to: 1)
        #expect(m.settings.categories.map(\.name) == ["Music", "Work", "Admin"])
    }

    @Test func movingACategoryUpLandsInTheTargetSlot() {
        let m = threeCategories()
        m.moveCategory(from: 2, to: 0)
        #expect(m.settings.categories.map(\.name) == ["Admin", "Work", "Music"])
    }

    @Test func movingToTheSlotItAlreadyOccupiesChangesNothing() {
        let m = threeCategories()
        m.moveCategory(from: 1, to: 1)
        #expect(m.settings.categories.map(\.name) == ["Work", "Music", "Admin"])
    }

    @Test func outOfRangeIndicesChangeNothing() {
        let m = threeCategories()
        m.moveCategory(from: 5, to: 0)
        m.moveCategory(from: 0, to: 9)
        m.moveCategory(from: -1, to: 1)
        #expect(m.settings.categories.map(\.name) == ["Work", "Music", "Admin"])
    }

    @Test func reorderingLeavesTheRecordsAlone() {
        let m = threeCategories()
        m.records = [Record(at: Date(), source: "manual", category: "Music")]
        m.moveCategory(from: 1, to: 0)
        #expect(m.todayCount(inCategory: "Music") == 1)
    }

    @Test func thePanelFollowsTheNewOrderWithTheBucketStillLast() {
        let m = threeCategories()
        m.moveCategory(from: 2, to: 0)
        #expect(m.todayProgress.map(\.name) == ["Admin", "Work", "Music", "General"])
    }

    @Test func theNewOrderSurvivesAReload() {
        let (m, url) = makeModel()
        m.settings.categoriesEnabled = true
        m.addCategory(name: "Work", dailyGoal: 4)
        m.addCategory(name: "Music", dailyGoal: 1)
        m.moveCategory(from: 1, to: 0)

        let reloaded = AppModel(storeURL: url)
        #expect(reloaded.settings.categories.map(\.name) == ["Music", "Work"])
    }

    // MARK: Nudging (keyboard and VoiceOver)

    @Test func nudgingMovesACategoryOneSlot() {
        let m = threeCategories()
        let admin = m.settings.categories[2].id
        m.nudgeCategory(id: admin, by: -1)
        #expect(m.settings.categories.map(\.name) == ["Work", "Admin", "Music"])
        m.nudgeCategory(id: admin, by: 1)
        #expect(m.settings.categories.map(\.name) == ["Work", "Music", "Admin"])
    }

    /// The row at either end has nowhere to go, and says so by doing nothing
    /// rather than by needing a special case at the call site.
    @Test func nudgingPastEitherEndChangesNothing() {
        let m = threeCategories()
        m.nudgeCategory(id: m.settings.categories[0].id, by: -1)
        m.nudgeCategory(id: m.settings.categories[2].id, by: 1)
        #expect(m.settings.categories.map(\.name) == ["Work", "Music", "Admin"])
    }

    @Test func nudgingAnUnknownCategoryChangesNothing() {
        let m = threeCategories()
        m.nudgeCategory(id: UUID(), by: 1)
        #expect(m.settings.categories.map(\.name) == ["Work", "Music", "Admin"])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
just test
```

Expected: compile failure — `value of type 'AppModel' has no member 'moveCategory'`.

- [ ] **Step 3: Write the implementation**

In `Sources/PomodoroCount/AppModel+Categories.swift`, add below the existing
`moveCategories(fromOffsets:toOffset:)`:

```swift
    /// Moves one category to a destination index.
    ///
    /// `Array.move(fromOffsets:toOffset:)` takes an *insertion offset measured
    /// before the removal*, not a destination index: moving a row down by one
    /// needs `to + 1`, and passing `to` unadjusted moves nothing at all — the
    /// row looks stuck to anything dragging it. That adjustment lives here so no
    /// caller has to know about it.
    ///
    /// Out-of-range indices, and a move to the slot the category already
    /// occupies, change nothing — so a drag that ends where it began writes
    /// nothing to the store.
    func moveCategory(from source: Int, to destination: Int) {
        let indices = settings.categories.indices
        guard indices.contains(source), indices.contains(destination),
              source != destination
        else { return }
        settings.categories.move(
            fromOffsets: IndexSet(integer: source),
            toOffset: destination > source ? destination + 1 : destination)
    }

    /// Moves a category one slot up (`-1`) or down (`+1`), for the keyboard and
    /// VoiceOver, which have no drag to offer. A category at either end simply
    /// stays put: `moveCategory` already ignores a destination off the end, so
    /// this needs no special case for it.
    func nudgeCategory(id: UUID, by delta: Int) {
        guard let index = settings.categories.firstIndex(where: { $0.id == id })
        else { return }
        moveCategory(from: index, to: index + delta)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
just test
```

Expected: all tests pass.

- [ ] **Step 5: Commit and push**

```bash
git add Sources/PomodoroCount/AppModel+Categories.swift Tests/PomodoroCountTests/CategoryManagementTests.swift
git commit -m "Move a category to a slot, off-by-one absorbed"
git push origin main
```

---

### Task 3: Split the category editor out of `SettingsTab.swift`

Pure code movement, no behaviour change. `SettingsTab.swift` is 383 lines doing
two jobs — app preferences and a category editor — and the next task adds to the
second. Doing the move on its own keeps that task's diff about the drag.

**Files:**
- Create: `Sources/PomodoroCount/CategoryEditor.swift`
- Modify: `Sources/PomodoroCount/SettingsTab.swift` (remove lines 76-92 and
  154-383, leaving app preferences)

**Interfaces:**
- Consumes: nothing.
- Produces: `CategoryList` — a `View` with no parameters, reading `AppModel` from
  the environment. `CategorySettingsRow(category:)`, `AddCategoryForm`,
  `RemoveCategoryConfirmation` and `FallbackNameField` keep their current
  signatures, just in a new file.

- [ ] **Step 1: Create the new file with the moved types**

Create `Sources/PomodoroCount/CategoryEditor.swift`. Move these four types out of
`SettingsTab.swift` **verbatim, including their doc comments**:
`AddCategoryForm`, `RemoveCategoryConfirmation`, `CategorySettingsRow`,
`FallbackNameField`.

Start the file with:

```swift
import SwiftUI

/// The Settings page's category editor: the list of categories, the row that
/// edits one, and the forms for adding and removing them. Split out of
/// `SettingsTab`, which was doing this and app preferences in one file.
```

Then add `CategoryList`, which is the `List` block lifted out of `SettingsTab`'s
body unchanged, so this task changes nothing about how it behaves:

```swift
/// The editable list of the user's categories.
struct CategoryList: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        // A List is required for SwiftUI to synthesise the drag-to-reorder
        // affordance for `.onMove` — a ForEach in a plain VStack never gets
        // one. It's given an explicit height sized to its row count so it
        // doesn't open its own internal scroller nested inside the tab's
        // outer ScrollView.
        List {
            ForEach(model.settings.categories) { category in
                CategorySettingsRow(category: category)
                    .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove { model.moveCategories(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(height: CGFloat(model.settings.categories.count) * CategorySettingsRow.rowHeight)
    }
}
```

- [ ] **Step 2: Replace the block in `SettingsTab.swift`**

In `SettingsTab.swift`, replace the whole `List { … }` expression and its three
modifiers (currently lines 76-92, from the `// A List is required` comment
through `.frame(height: …)`) with:

```swift
                        CategoryList()
```

Then delete `AddCategoryForm`, `RemoveCategoryConfirmation`,
`CategorySettingsRow` and `FallbackNameField` from the bottom of the file — they
now live in `CategoryEditor.swift`.

- [ ] **Step 3: Verify it builds and nothing changed**

```bash
just build && just test
```

Expected: build succeeds, all tests pass. Test count is unchanged from Task 2 —
this task adds no behaviour, so it adds no tests.

- [ ] **Step 4: Check Settings still looks right**

```bash
just install
```

Open the menu bar panel → Settings, turn on **Use categories**, and confirm the
category rows, the add button, the remove confirmation and the "Everything else"
field all render and behave exactly as before.

- [ ] **Step 5: Commit and push**

```bash
git add Sources/PomodoroCount/CategoryEditor.swift Sources/PomodoroCount/SettingsTab.swift
git commit -m "Give the category editor its own file"
git push origin main
```

---

### Task 4: The grip handle and the drag

The substance. `CategoryList` swaps its `List` for a `VStack` that measures its
own row height, each row gains a grip on its leading edge, and dragging that grip
reorders. `moveCategories(fromOffsets:toOffset:)` loses its last caller and goes.

**Files:**
- Modify: `Sources/PomodoroCount/CategoryEditor.swift` (rewrite `CategoryList`;
  delete `CategorySettingsRow.rowHeight`)
- Modify: `Sources/PomodoroCount/AppModel+Categories.swift` (delete
  `moveCategories(fromOffsets:toOffset:)`)
- Test: `Tests/PomodoroCountTests/CategoryManagementTests.swift` (delete
  `reorderingChangesDisplayOrder`)

**Interfaces:**
- Consumes: `Reorder.destination(from:translation:pitch:count:)` from Task 1 and
  `AppModel.moveCategory(from:to:)` from Task 2.
- Produces: nothing new for later tasks; Task 5 adds modifiers to
  `CategoryList.row(_:at:)`.

- [ ] **Step 1: Delete the dead method and its test**

`moveCategories(fromOffsets:toOffset:)` exists only to feed `List.onMove`, which
this task removes. Delete it from `AppModel+Categories.swift:178-180`:

```swift
    func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) {
        settings.categories.move(fromOffsets: source, toOffset: destination)
    }
```

And delete the test that covers it, in `CategoryManagementTests.swift`:

```swift
    @Test func reorderingChangesDisplayOrder() {
        let m = configured()
        m.moveCategories(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(m.settings.categories.map(\.name) == ["Music", "Work"])
    }
```

Its coverage is replaced by the `moveCategory` tests added in Task 2.

- [ ] **Step 2: Delete the hardcoded row height**

In `CategoryEditor.swift`, delete `CategorySettingsRow.rowHeight` and the comment
block above it (currently the `/// Measured height of one row inside the List…`
doc comment through `static let rowHeight: CGFloat = 32`). The height is measured
at layout time now, so the hand-measured constant and its "re-measure this
number" warning both go.

- [ ] **Step 3: Rewrite `CategoryList`**

Replace the whole of `CategoryList` in `CategoryEditor.swift` with:

```swift
/// The editable list of the user's categories, reordered by dragging a row's
/// grip handle.
///
/// A plain `VStack` rather than a `List`. `List` synthesises `.onMove`, but its
/// drag starts anywhere in the row, and this row is a text field, a stepper and
/// a button edge to edge — there was nothing to grab, so the reordering it
/// offered was unreachable. A `List` nested in the Settings `ScrollView` also
/// opened a scroller of its own unless given an explicit height, which meant
/// hardcoding a row height and re-measuring it by hand whenever the row changed.
/// The stack drops both problems: the grip is the only drag source, and the row
/// height is measured at layout time.
struct CategoryList: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var palette

    /// The gap between rows. Half the drag pitch, so it is named rather than
    /// inlined into the `VStack`.
    private static let spacing: CGFloat = 6

    /// One row's measured height. Zero until the first layout has run, which
    /// `Reorder.destination` treats as "cannot move yet".
    @State private var rowHeight: CGFloat = 0
    @State private var drag: DragState?

    /// A reorder in progress. `startIndex` is where the row was picked up,
    /// `currentIndex` where it sits now; they diverge as the drag commits moves,
    /// and the gap between them is what keeps the row under the pointer.
    private struct DragState {
        let id: UUID
        let startIndex: Int
        var currentIndex: Int
        var translation: CGFloat = 0
    }

    /// Distance from one row's top edge to the next.
    private var pitch: CGFloat { rowHeight + Self.spacing }

    /// Where the dragged row is drawn: the raw translation less the distance
    /// already absorbed by moves it has committed. Without that subtraction the
    /// row would jump a full slot away from the pointer every time it swapped.
    private var visualOffset: CGFloat {
        guard let drag else { return 0 }
        return drag.translation - CGFloat(drag.currentIndex - drag.startIndex) * pitch
    }

    var body: some View {
        VStack(spacing: Self.spacing) {
            ForEach(Array(model.settings.categories.enumerated()), id: \.element.id) { index, category in
                row(category, at: index)
            }
        }
    }

    private func row(_ category: Category, at index: Int) -> some View {
        let dragging = drag?.id == category.id
        return HStack(spacing: 6) {
            grip(for: category, at: index)
            CategorySettingsRow(category: category)
        }
        .background {
            // Every row is the same shape, so they all report the same height
            // and it does not matter which one lands last. Measured rather than
            // hardcoded: the old `List` needed a fixed row height that had to be
            // re-measured by hand whenever the row's font or padding changed.
            GeometryReader { geo in
                // `.task(id:)` rather than `.onChange(of:initial:)`: it runs
                // after the layout that produced the height, so writing state
                // here cannot land in the middle of a view update.
                Color.clear.task(id: geo.size.height) { rowHeight = geo.size.height }
            }
        }
        .offset(y: dragging ? visualOffset : 0)
        .scaleEffect(dragging ? 1.02 : 1)
        .shadow(color: .black.opacity(dragging ? 0.28 : 0), radius: 7, y: 3)
        // Lifted clear of its neighbours, so it passes over them rather than
        // under while it is being dragged.
        .zIndex(dragging ? 1 : 0)
    }

    /// The drag handle. Deliberately not a `Button`: it performs no action when
    /// clicked, and button semantics would promise one. The reorder actions for
    /// VoiceOver and the keyboard live on the row instead.
    private func grip(for category: Category, at index: Int) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(drag?.id == category.id ? palette.text : palette.textDim)
            .frame(width: 12, height: 22)
            .contentShape(Rectangle())
            .onHover { inside in
                // The open hand is the macOS convention for "this can be
                // dragged"; the gesture swaps it for the closed one while a drag
                // is actually running.
                if inside { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
            }
            .gesture(dragGesture(for: category, at: index))
            .help("Drag to reorder")
    }

    /// `minimumDistance: 3` so a stray click on the grip is not a reorder.
    private func dragGesture(for category: Category, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                if drag == nil {
                    drag = DragState(id: category.id, startIndex: index, currentIndex: index)
                    NSCursor.closedHand.set()
                }
                guard var state = drag else { return }
                state.translation = value.translation.height

                let destination = Reorder.destination(
                    from: state.startIndex,
                    translation: state.translation,
                    pitch: pitch,
                    count: model.settings.categories.count)

                if destination != state.currentIndex {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        model.moveCategory(from: state.currentIndex, to: destination)
                    }
                    state.currentIndex = destination
                }
                drag = state
            }
            .onEnded { _ in
                NSCursor.openHand.set()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = nil }
            }
    }
}
```

Add `import AppKit` beneath `import SwiftUI` at the top of `CategoryEditor.swift`
— `NSCursor` comes from there.

- [ ] **Step 4: Build and run the tests**

```bash
just build && just test
```

Expected: build succeeds, all tests pass. The suite is smaller by one test
(`reorderingChangesDisplayOrder`, deleted in Step 1) and otherwise unchanged —
this task adds no testable logic of its own, only the wiring between Task 1's
arithmetic and Task 2's mutation.

- [ ] **Step 5: Drive it in the running app**

```bash
just install
```

Open the panel → Settings → **Use categories**, add three categories, then check:

1. Each row has a three-line grip on its left; hovering it shows the open-hand
   cursor.
2. Dragging a grip lifts the row, the others slide aside, and the order commits
   as you cross each neighbour.
3. Releasing settles the row; the Focus panel shows the same new order.
4. The name field, the goal stepper and the remove button all still work — a
   drag inside the name field selects text, it does not reorder.
5. A single click on the grip does nothing.
6. The Settings page has no second scrollbar inside the category list.

One thing to watch at step 2: the committed move is animated, which also animates
the dragged row's own layout position while `visualOffset` compensates for it
instantly. If the dragged row visibly lags or stutters behind the pointer just
after a swap, exempt it from that animation by adding
`.animation(nil, value: drag?.currentIndex)` to the `.offset` in `row(_:at:)`.
Leave it out if the drag already tracks cleanly — do not add it speculatively.

- [ ] **Step 6: Commit and push**

```bash
git add Sources/PomodoroCount/CategoryEditor.swift Sources/PomodoroCount/AppModel+Categories.swift Tests/PomodoroCountTests/CategoryManagementTests.swift
git commit -m "Drag a category by its grip to reorder it"
git push origin main
```

---

### Task 5: Reordering without a mouse

The `List` gave VoiceOver a reorder action and gave keyboard users nothing —
macOS list reordering is mouse-only. Replacing it must not lose the former, and
this is a cheap chance to gain the latter. `nudgeCategory` already exists and is
tested from Task 2; this wires it to the row.

**Files:**
- Modify: `Sources/PomodoroCount/CategoryEditor.swift` (`CategoryList.row(_:at:)`)
- Modify: `CHANGELOG.md` (the `[Unreleased]` section)

**Interfaces:**
- Consumes: `AppModel.nudgeCategory(id:by:)` from Task 2.
- Produces: nothing.

- [ ] **Step 1: Add the accessibility actions**

In `CategoryList.row(_:at:)`, add to the end of the modifier chain, after
`.zIndex(dragging ? 1 : 0)`:

```swift
        // A drag is the only way to reorder with a mouse, so VoiceOver and the
        // keyboard get these instead. They sit on the row, which already carries
        // the category's name, rather than on the grip, which is a bare glyph.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(category.name)
        .accessibilityAction(named: "Move up") { nudge(category, by: -1) }
        .accessibilityAction(named: "Move down") { nudge(category, by: 1) }
```

And add this method to `CategoryList`, below `dragGesture(for:at:)`:

```swift
    /// Animates a one-slot nudge, so a keyboard move reads the same as a drag.
    /// A row at either end stays put — `nudgeCategory` ignores a destination off
    /// the end, so there is no special case here.
    private func nudge(_ category: Category, by delta: Int) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            model.nudgeCategory(id: category.id, by: delta)
        }
    }
```

- [ ] **Step 2: Build and run the tests**

```bash
just build && just test
```

Expected: build succeeds, all tests pass. No new tests: the logic being wired up
is `nudgeCategory`, already covered by the three nudge tests from Task 2, and the
project's `AccessibilityTests` suite states in its own header that labels
attached in the view layer cannot be asserted headlessly.

- [ ] **Step 3: Verify with VoiceOver**

```bash
just install
```

Turn VoiceOver on (⌘F5), open Settings with categories on, navigate to a category
row, and press ⌃⌥⌘Space to list its actions. Confirm "Move up" and "Move down"
appear and that choosing one reorders the list. Confirm a row at the top has no
effect from "Move up" — it should stay put rather than doing anything odd. Turn
VoiceOver off when done.

- [ ] **Step 4: Write the changelog entry**

In `CHANGELOG.md`, replace the `[Unreleased]` section's `Nothing yet.` with:

```markdown
### Added

- **Reorder categories** — drag a category by the grip handle on its Settings
  row to change the order categories appear in, both in Settings and in the
  Focus panel. Reachable without a mouse too: each row carries "Move up" and
  "Move down" actions for VoiceOver and the keyboard.
```

- [ ] **Step 5: Commit and push**

```bash
git add Sources/PomodoroCount/CategoryEditor.swift CHANGELOG.md
git commit -m "Reorder categories without a mouse"
git push origin main
```

---

## Done when

- `just test` passes with the ReorderTests suite and the new `moveCategory` and
  `nudgeCategory` tests, and without `reorderingChangesDisplayOrder`.
- Dragging a grip in Settings reorders categories, and the Focus panel agrees.
- The name field, goal stepper and remove button are unaffected by the grip.
- `CategorySettingsRow.rowHeight` and `AppModel.moveCategories` are both gone.
- `SettingsTab.swift` holds app preferences only; the category editor lives in
  `CategoryEditor.swift`.
- The `[Unreleased]` changelog section describes the feature.
