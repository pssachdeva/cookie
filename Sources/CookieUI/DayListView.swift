import SwiftUI
import CookieCore

/// The single entry field. Lives outside the day list so its draft survives
/// switching days, and always adds to the currently selected day.
public struct EntryBar: View {
    @Environment(TaskStore.self) private var store
    @Environment(DayNavigation.self) private var navigation
    @Binding var draft: String
    @FocusState private var focused: Bool
    let day: CalendarDay
    /// Bumped to put the cursor in the field, for windows (the menu bar
    /// panel) that become active after the field appears.
    var focusRequest = 0

    public init(draft: Binding<String>, day: CalendarDay, focusRequest: Int = 0) {
        _draft = draft
        self.day = day
        self.focusRequest = focusRequest
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(focused ? Color.cookieAccent : .secondary)
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($focused)
                .onSubmit(submit)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(focused ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.cookieAccent.opacity(focused ? 0.5 : 0), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: focused)
        #if os(macOS)
        // Ready to type on launch. Not on the iPhone, where the keyboard
        // would cover half the screen before anything is asked of it.
        .onAppear { focused = true }
        #endif
        .onChange(of: focusRequest) { focused = true }
    }

    private var placeholder: String {
        let today = navigation.today
        if day == today { return "Add a task for today" }
        if day == today.adding(days: 1) { return "Add a task for tomorrow" }
        if day == today.adding(days: -1) { return "Add a task for yesterday" }
        let within = abs(day.date().timeIntervalSince(today.date())) < 6 * 86_400
        let label = day.date().formatted(within ? .dateTime.weekday(.wide) : .dateTime.month(.abbreviated).day())
        return "Add a task for \(label)"
    }

    private func submit() {
        // Enter adds the task, clears the field, and keeps focus. The store
        // ignores whitespace-only input.
        store.add(draft, to: day)
        draft = ""
        focused = true
    }
}

public struct DayListView: View {
    @Environment(TaskStore.self) private var store
    @Environment(DayNavigation.self) private var navigation
    @Environment(DragController.self) private var drag
    @Environment(\.undoManager) private var undoManager
    // Animated @State mirrors of the persisted section states; see
    // CalendarView for why @AppStorage cannot be animated directly.
    @AppStorage("completedExpanded") private var storedCompletedExpanded = false
    @AppStorage("earlierExpanded") private var storedEarlierExpanded = true
    @State private var completedExpanded = false
    @State private var earlierExpanded = true
    /// True once rows have scrolled under the pinned day header.
    @State private var scrolled = false

    let day: CalendarDay
    /// Off in the menu bar panel, which shows the date in its own header.
    var showsHeader = true

    public init(day: CalendarDay, showsHeader: Bool = true) {
        self.day = day
        self.showsHeader = showsHeader
    }

    private var isToday: Bool { day == navigation.today }

    public var body: some View {
        let active = store.activeTasks(on: day)
        let completed = store.completedTasks(on: day)
        let earlier = isToday ? store.earlierUnfinished(before: day) : []

        ScrollView {
            // The day header is pinned so the list never loses its date; a
            // hairline under it appears once rows scroll beneath.
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                Section {
                    if !earlier.isEmpty {
                        SectionHeader(title: "Earlier", count: earlier.count, expanded: $earlierExpanded)
                        if earlierExpanded {
                            ForEach(earlier) { task in
                                TaskRow(task: task, showsDate: true, onDelete: delete)
                                    .transition(rowTransition)
                            }
                        }
                        SectionHeader(title: "Today", count: active.count)
                            .padding(.top, 4)
                    }

                    // Plain VStack so the container has a frame even when empty,
                    // which anchors the drag insertion line on an empty day.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(active) { task in
                            TaskRow(task: task, showsDate: false, onDelete: delete)
                                .transition(rowTransition)
                        }
                    }
                    .reportFrame { drag.activeListFrame = $0 }
                    .onChange(of: active.map(\.id), initial: true) { _, ids in drag.activeRows = ids }

                    if active.isEmpty && earlier.isEmpty {
                        Text(completed.isEmpty ? "Nothing planned" : "All done")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }

                    if !completed.isEmpty {
                        completedSection(completed)
                    }
                } header: {
                    if showsHeader { dayHeader }
                }
            }
            // Extra room so the last row clears the window's rounded corner.
            .padding(.bottom, 28)
            .animation(.snappy(duration: 0.3), value: store.tasks)
        }
        .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 0.5 }) { _, isScrolled in
            scrolled = isScrolled
        }
        .reportFrame { drag.listFrame = $0 }
        .onAppear {
            completedExpanded = storedCompletedExpanded
            earlierExpanded = storedEarlierExpanded
        }
        .onChange(of: completedExpanded) { _, value in storedCompletedExpanded = value }
        .onChange(of: earlierExpanded) { _, value in storedEarlierExpanded = value }
    }

    private var dayHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(day.date().formatted(.dateTime.weekday(.wide)))
                .font(.title3.weight(.semibold))
            Text(day.date().formatted(.dateTime.month(.wide).day()))
                .font(.title3)
                .foregroundStyle(.secondary)
            if isToday {
                Text("Today")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.cookieAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.cookieAccent.opacity(0.14)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background(.background)
        .overlay(alignment: .bottom) {
            Divider().opacity(scrolled ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.15), value: scrolled)
    }

    private func completedSection(_ completed: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Completed", count: completed.count, expanded: $completedExpanded)

            if completedExpanded {
                ForEach(completed) { task in
                    TaskRow(task: task, showsDate: false, onDelete: delete)
                        .transition(rowTransition)
                }
            }
        }
        .padding(.top, 6)
    }

    private var rowTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -4)),
            removal: .opacity
        )
    }

    private func delete(_ id: UUID) {
        store.delete(id)
        undoManager?.registerUndo(withTarget: store) { store in
            MainActor.assumeIsolated { store.restore(id) }
        }
        undoManager?.setActionName("Delete Task")
    }
}

/// Section header: a left-aligned "Title  N". With an `expanded` binding it
/// is a collapse toggle with a chevron that turns like the month title's;
/// without one it is a plain label.
struct SectionHeader: View {
    let title: String
    let count: Int
    var expanded: Binding<Bool>? = nil

    var body: some View {
        if let expanded {
            Button {
                withAnimation(.snappy(duration: 0.25)) { expanded.wrappedValue.toggle() }
            } label: {
                label(chevronOpen: expanded.wrappedValue)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(count)")
            .accessibilityValue(expanded.wrappedValue ? "expanded" : "collapsed")
        } else {
            label(chevronOpen: nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title), \(count)")
        }
    }

    private func label(chevronOpen: Bool?) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            if let chevronOpen {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(chevronOpen ? 0 : -90))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

struct TaskRow: View {
    @Environment(TaskStore.self) private var store
    @Environment(DayNavigation.self) private var navigation
    @Environment(DragController.self) private var drag
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager
    @Environment(\.taskDraggingEnabled) private var draggingEnabled
    let task: TaskItem
    /// Shown for earlier-unfinished rows so their assigned day is visible.
    let showsDate: Bool
    let onDelete: (UUID) -> Void

    // Local animation state so the check, the strikethrough sweep, and the
    // removal can play in sequence before the store changes.
    @State private var checked: Bool
    @State private var strike: CGFloat
    @State private var completing = false
    /// Rolling cookie: true once it leaves the checkbox; progress 0...1
    /// along the row.
    @State private var rolling = false
    @State private var roll: CGFloat = 0
    /// Checkbox frame in the row's own space, for the wipe edge and the
    /// rolling cookie's path.
    @State private var checkFrame: CGRect = .zero
    @State private var hovering = false

    // Inline editing: the text swaps for a field holding a working copy,
    // committed on Enter or when focus leaves, discarded on Escape.
    @State private var editing = false
    @State private var editText = ""
    @FocusState private var editFocused: Bool

    private var rowSpace: String { "row-\(task.id.uuidString)" }

    // Drag bookkeeping: the row's own frame for the grab offset, and whether
    // this gesture already started a session (so a cancelled drag doesn't
    // restart while the button is still down).
    @State private var frame: CGRect = .zero
    @State private var dragStarted = false

    private var isBeingDragged: Bool { drag.session?.taskID == task.id }

    init(task: TaskItem, showsDate: Bool, onDelete: @escaping (UUID) -> Void) {
        self.task = task
        self.showsDate = showsDate
        self.onDelete = onDelete
        _checked = State(initialValue: task.isCompleted)
        _strike = State(initialValue: task.isCompleted ? 1 : 0)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            CheckCircle(checked: checked, cookieHidden: rolling, action: toggle)
                .accessibilityLabel(task.text)
                .accessibilityValue(checked ? "completed" : "not completed")
                .onGeometryChange(for: CGRect.self, of: { [rowSpace] in $0.frame(in: .named(rowSpace)) }) { checkFrame = $0 }

            Group {
                if editing {
                    editor
                } else {
                    label
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsDate {
                // Every Earlier row is past due; the red matches the
                // calendar's filled past-due dot.
                Text(task.day.date().formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.overdue.opacity(0.9))
            }
        }
        .coordinateSpace(name: rowSpace)
        // While the cookie rolls, everything left of its center is wiped
        // away, ring included, so the row is blank once it leaves.
        .mask {
            // Padded so the cookie, which overhangs the ring, isn't trimmed.
            if rolling {
                WipeMask(progress: roll, startX: checkFrame.midX, rowWidth: frame.width)
                    .padding(-4)
            } else {
                Rectangle()
                    .padding(-4)
            }
        }
        // The rolling cookie sits outside the mask, centered on the
        // checkbox's position (which is the first line of wrapped text) and
        // travels the row's full width so it rolls off the clipped edge.
        .overlay(alignment: .topLeading) {
            if rolling {
                CookieGlyph()
                    .frame(width: CheckCircle.cookieSize, height: CheckCircle.cookieSize)
                    .rotationEffect(.degrees(Double(roll) * 540))
                    .position(x: checkFrame.midX + roll * frame.width, y: checkFrame.midY)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        // Hover highlight, inset from the window edges. Off during drags and
        // the completion roll, where it would flicker under the pointer.
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(editing ? 0.07 : hovering && !drag.isDragging && !completing ? 0.05 : 0))
                .padding(.horizontal, 8)
        }
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
        }
        .clipped()
        .contentShape(Rectangle())
        // Double-clicking anywhere in the row edits it, not only on the
        // words. Off while editing, so a double-click in the field selects
        // a word as usual.
        .gesture(TapGesture(count: 2).onEnded(beginEditing), including: editing ? .none : .all)
        .opacity(isBeingDragged ? 0.25 : 1)
        .reportFrame { frame = $0; drag.rowFrames[task.id] = $0 }
        #if os(macOS)
        // No row drag while editing, so dragging selects text instead, or
        // where dragging is turned off (the menu bar panel).
        .gesture(dragGesture, including: editing || !draggingEnabled ? .subviews : .all)
        #else
        // Press and hold to lift the row, then drag; a hold without moving
        // opens the context menu instead.
        .onDrag {
            drag.beginTouch(task: task)
            return NSItemProvider(object: task.id.uuidString as NSString)
        }
        #endif
        .contextMenu {
            Button("Edit", action: beginEditing)
            if showsDate {
                Button("Move to Today") { store.move(task.id, to: navigation.today) }
            }
            Button("Delete", role: .destructive) { onDelete(task.id) }
        }
    }

    #if os(macOS)
    private var dragGesture: some Gesture {
        // Only starts the drag; the controller then follows the mouse on its
        // own, since this row can disappear mid-drag when the list changes.
        DragGesture(minimumDistance: 4, coordinateSpace: .named(windowSpace))
            .onChanged { value in
                if !dragStarted {
                    dragStarted = true
                    drag.begin(task: task, rowFrame: frame, grabbedAt: value.startLocation, now: value.location)
                }
            }
            .onEnded { _ in
                // Normally the controller has already ended the drag on
                // mouse-up; this is a no-op then.
                drag.end()
                dragStarted = false
            }
    }
    #endif

    /// Same font and wrapping as the label, so entering edit mode doesn't
    /// shift the row.
    private var editor: some View {
        TextField("Task", text: $editText, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.body)
            .focused($editFocused)
            .onSubmit(commitEdit)
            #if os(macOS)
            .onExitCommand(perform: cancelEdit)
            #endif
            .onChange(of: editFocused) { _, focused in
                // Clicking elsewhere commits, like renaming in Finder.
                if !focused { commitEdit() }
            }
            .onAppear { editFocused = true }
    }

    private func beginEditing() {
        guard !editing, !completing else { return }
        editText = task.text
        editing = true
    }

    /// Saves the edit. Text that normalizes to nothing reverts rather than
    /// deleting, since Delete has its own menu item.
    private func commitEdit() {
        guard editing else { return }
        editing = false
        let id = task.id
        let old = task.text
        guard let new = TaskText.normalized(editText), new != old else { return }
        store.updateText(id, new)
        undoManager?.registerUndo(withTarget: store) { store in
            MainActor.assumeIsolated { store.updateText(id, old) }
        }
        undoManager?.setActionName("Edit Task")
    }

    private func cancelEdit() {
        editing = false
    }

    /// Plain text with a struck copy masked from the leading edge, so the
    /// strikethrough sweeps left to right (and per line for wrapped text).
    private var label: some View {
        let base = Text(task.text)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
        return ZStack(alignment: .leading) {
            base.foregroundStyle(checked ? .secondary : .primary)
            base.strikethrough(true, color: .secondary)
                .foregroundStyle(.secondary)
                .mask(alignment: .leading) {
                    StrikeMask(progress: strike)
                }
        }
    }

    private func toggle() {
        guard !completing else { return }
        if task.isCompleted {
            // Unchecking is immediate: the row returns to its old position.
            store.setCompleted(task.id, false)
            return
        }
        completing = true
        if reduceMotion {
            checked = true
            strike = 1
            store.setCompleted(task.id, true)
            return
        }
        // 1. The circle fills with the cookie.
        withAnimation(.spring(duration: 0.3, bounce: 0.35)) { checked = true }
        // 2. The cookie rolls off to the right, sweeping the strikethrough
        //    behind it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            rolling = true
            withAnimation(.easeIn(duration: 0.6)) { roll = 1 }
        }
        // 3. The row clears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.3)) { store.setCompleted(task.id, true) }
        }
    }
}

/// Mask for the struck copy of the text: a fraction of its width from the
/// leading edge. Animatable so the sweep is per-frame.
struct StrikeMask: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width * progress, height: rect.height))
    }
}

/// Mask for the whole row while the cookie rolls: only what lies right of
/// the cookie's center stays visible. Animatable so the edge follows the
/// cookie's interpolated position every frame.
struct WipeMask: Shape {
    var progress: CGFloat
    var startX: CGFloat
    var rowWidth: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let edge = startX + progress * rowWidth
        return Path(CGRect(x: edge, y: rect.minY, width: max(0, rect.maxX - edge), height: rect.height))
    }
}

struct CheckCircle: View {
    let checked: Bool
    /// True while the cookie is rolling away, so the circle shows empty.
    var cookieHidden = false
    let action: () -> Void

    static let ringSize: CGFloat = 18
    /// Larger than the ring so the cookie covers it completely.
    static let cookieSize: CGFloat = 22
    /// Hit area beyond the ring: a fingertip needs far more than a pointer.
    #if os(macOS)
    static let touchSlop: CGFloat = 2
    #else
    static let touchSlop: CGFloat = 12
    #endif

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Warms to the accent on hover to show it is the click target.
                Circle()
                    .strokeBorder(
                        hovering && !checked ? Color.cookieAccent : Color.secondary.opacity(0.6),
                        lineWidth: 1.5
                    )
                    .frame(width: Self.ringSize, height: Self.ringSize)
                CookieGlyph()
                    .frame(width: Self.cookieSize, height: Self.cookieSize)
                    .scaleEffect(checked && !cookieHidden ? 1 : 0.3)
                    .opacity(checked && !cookieHidden ? 1 : 0)
            }
            .frame(width: Self.ringSize, height: Self.ringSize)
            .padding(Self.touchSlop)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The extra hit area around the ring doesn't take up layout space.
        .padding(-Self.touchSlop)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
        }
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
    }
}

/// The app's cookie. On the Mac, drawn from the bundled SVG (the same source
/// as the Dock icon), with the Dock icon as a fallback when running outside
/// the bundle; on the iPhone, the "Cookie" image in the app's asset catalog,
/// rendered from the same SVG.
struct CookieGlyph: View {
    #if os(macOS)
    private static let image: NSImage? = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }()
    #endif

    var body: some View {
        #if os(macOS)
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Circle().fill(.orange)
        }
        #else
        Image("Cookie")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
        #endif
    }
}

extension EnvironmentValues {
    /// Whether task rows can be dragged to move them. Off in the menu bar
    /// panel, which only shows today and has nowhere to drag to.
    @Entry public var taskDraggingEnabled = true
}
