import SwiftUI
import CookieCore
import CookieUI

/// The main window: the shared planner, sized like a phone, with the
/// calendar header moved up into the hidden title bar beside the traffic
/// lights.
struct MainWindowView: View {
    let store: TaskStore

    var body: some View {
        DayPlannerView(store: store)
            .environment(\.calendarHeaderMetrics, CalendarHeaderMetrics(height: 28, leadingInset: 58))
            .frame(minWidth: Self.minSize.width, idealWidth: 360, minHeight: Self.minSize.height, idealHeight: 680)
            .background(WindowSizeLimits(min: Self.minSize, max: Self.maxSize, initial: Self.defaultSize))
            // Content starts at the window's top edge; the calendar header
            // shares the title bar's row with the traffic lights. Last in the
            // chain so clipping inside the planner covers the full window,
            // not only the area below the title bar.
            .ignoresSafeArea(.container, edges: .top)
    }

    static let minSize = CGSize(width: 320, height: 560)
    static let defaultSize = CGSize(width: 360, height: 680)
    /// Width is capped so the window can't grow past the layout; height is
    /// free so a long list can have more room.
    static let maxSize = CGSize(width: 440, height: 4000)
}

/// Applies content size limits to the hosting NSWindow, and the default size
/// on a first launch. SwiftUI's `windowResizability(.contentSize)` was
/// unreliable with a flexible frame (it opened the window at the minimum
/// width), and macOS's per-app window placement memory can reopen the window
/// at a stale size even when the app has no saved frame of its own, so both
/// are handled on the window directly.
struct WindowSizeLimits: NSViewRepresentable {
    let min: CGSize
    let max: CGSize
    let initial: CGSize

    func makeNSView(context: Context) -> LimitView {
        let view = LimitView()
        view.limits = (min, max)
        view.initial = initial
        return view
    }

    func updateNSView(_ view: LimitView, context: Context) {
        view.limits = (min, max)
        view.initial = initial
    }

    final class LimitView: NSView {
        var limits: (CGSize, CGSize) = (.zero, .zero)
        var initial: CGSize = .zero
        private var applied = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Deferred: applying limits while the window is still being set
            // up clamps its placeholder frame before SwiftUI sizes it.
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        private func apply() {
            guard !applied, let window, window.isVisible else { return }
            applied = true
            window.contentMinSize = limits.0
            window.contentMaxSize = limits.1
            // SwiftUI stores the frame under this key once the user has
            // used the window; absent that, enforce the default size.
            if UserDefaults.standard.string(forKey: "NSWindow Frame \(window.identifier?.rawValue ?? "main")") == nil {
                window.setContentSize(initial)
            }
        }
    }
}
