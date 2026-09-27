import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    /// Toasted caramel, taken from the cookie icon's dough. Darker in light
    /// mode so white text on it and it on white both stay legible.
    public static let cookieAccent: Color = {
        let dark = (red: 0.79, green: 0.51, blue: 0.21)   // #C98236
        let light = (red: 0.66, green: 0.37, blue: 0.13)  // #A85F22
        #if os(macOS)
        return Color(nsColor: NSColor(name: "cookieAccent") { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #else
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #endif
    }()

    /// Past-due marker, shared by the calendar dots and the Earlier section's
    /// dates. Red rather than orange so it stays distinct from the accent.
    public static let overdue = Color.red

    /// Tint for the calendar's surface, which sets it apart from the list.
    static let calendarSurface = Color.primary.opacity(0.035)
}

/// Compact header control: a larger hit area than its glyph and a soft
/// rounded highlight on hover and press.
public struct HeaderButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HeaderButtonBody(configuration: configuration)
    }

    private struct HeaderButtonBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 6)
                .frame(minWidth: Self.minSize.width, minHeight: Self.minSize.height)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : hovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }

        /// Touch targets need more room than pointer targets.
        #if os(macOS)
        static let minSize = CGSize(width: 26, height: 24)
        #else
        static let minSize = CGSize(width: 36, height: 36)
        #endif
    }
}
