import SwiftUI
import AppKit
import CookieCore
import CookieUI

/// The menu bar panel: today's tasks, with the Earlier and Completed
/// sections and an entry field, plus a way into the main window. It always
/// shows today, whatever the main window is showing.
struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var navigation: DayNavigation
    @State private var drag: DragController
    @State private var draft = ""
    @State private var panel: NSWindow?
    @State private var focusRequest = 0

    init(store: TaskStore) {
        // Its own navigation, so it tracks today (midnight included) on its
        // own and never follows the main window's selection.
        let navigation = DayNavigation()
        _navigation = State(initialValue: navigation)
        _drag = State(initialValue: DragController(navigation: navigation, store: store))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            EntryBar(draft: $draft, day: navigation.today, focusRequest: focusRequest)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            DayListView(day: navigation.today, showsHeader: false)
                .id(navigation.today)
        }
        .frame(width: 320, height: 440)
        .coordinateSpace(name: windowSpace)
        .environment(navigation)
        .environment(drag)
        .environment(\.taskDraggingEnabled, false)
        .background(WindowReader { panel = $0 })
        .onExitCommand { dismissPanel() }
        // The panel stays alive between openings and doesn't take the
        // keyboard on its own, so each time it comes on screen make it the
        // key window and put the cursor in the entry field.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            guard let panel, note.object as? NSWindow === panel,
                  panel.occlusionState.contains(.visible) else { return }
            NSApp.activate()
            panel.makeKey()
            focusRequest += 1
        }
    }

    /// Closes the panel by clicking Cookie's own menu bar item, the same
    /// toggle a person uses. Closing the window directly would leave the
    /// item thinking the panel is open, and swallow the next click on it.
    private func dismissPanel() {
        let button = NSApp.windows
            .filter { $0.className == "NSStatusBarWindow" }
            .lazy
            .compactMap { $0.contentView.flatMap(Self.statusButton(in:)) }
            .first
        if let button {
            button.performClick(nil)
        } else {
            panel?.close()
        }
    }

    private static func statusButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap(statusButton(in:)).first
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(navigation.today.date().formatted(.dateTime.weekday(.wide)))
                .font(.title3.weight(.semibold))
            Text(navigation.today.date().formatted(.dateTime.month(.wide).day()))
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button {
                openWindow(id: "main")
                NSApp.activate()
                dismissPanel()
            } label: {
                Image(systemName: "macwindow")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(HeaderButtonStyle())
            .foregroundStyle(.secondary)
            .help("Open the Cookie window")
            .accessibilityLabel("Open window")
        }
    }
}

/// Reports the window a view is in.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = window
            DispatchQueue.main.async { [onWindow] in onWindow?(window) }
        }
    }
}

extension NSImage {
    /// Menu bar icon: a cookie with a bite out of it and chips punched
    /// through. A template image, so macOS tints it for light and dark menu
    /// bars and for the highlighted state.
    static let cookieMenuBarIcon: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 7.5

            context.setFillColor(NSColor.black.cgColor)
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                           width: radius * 2, height: radius * 2))

            // Everything below is cut out of the disk.
            context.setBlendMode(.clear)
            // The bite, from the upper right.
            let bite: CGFloat = 3.4
            context.fillEllipse(in: CGRect(x: center.x + 4.6 - bite, y: center.y - 6.4 - bite,
                                           width: bite * 2, height: bite * 2))
            // Chips, as (x, y, radius) offsets from the center.
            let chips: [(CGFloat, CGFloat, CGFloat)] = [
                (-3.3, -2.2, 1.3), (1.2, 0.6, 1.2), (-1.4, 3.6, 1.1), (3.6, 3.0, 1.0), (-4.2, 1.8, 0.8),
            ]
            for (dx, dy, r) in chips {
                context.fillEllipse(in: CGRect(x: center.x + dx - r, y: center.y + dy - r,
                                               width: r * 2, height: r * 2))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cookie"
        return image
    }()
}
