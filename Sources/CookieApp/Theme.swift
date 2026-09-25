import SwiftUI
import AppKit

extension Color {
    /// Toasted caramel, taken from the cookie icon's dough. Darker in light
    /// mode so white text on it and it on white both stay legible.
    static let cookieAccent = Color(nsColor: NSColor(name: "cookieAccent") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.79, green: 0.51, blue: 0.21, alpha: 1)  // #C98236
            : NSColor(srgbRed: 0.66, green: 0.37, blue: 0.13, alpha: 1)  // #A85F22
    })

    /// Past-due marker, shared by the calendar dots and the Earlier section's
    /// dates. Red rather than orange so it stays distinct from the accent.
    static let overdue = Color(nsColor: .systemRed)

    /// Tint for the calendar's surface, which sets it apart from the list.
    static let calendarSurface = Color.primary.opacity(0.035)
}

/// Compact header control: a larger hit area than its glyph and a soft
/// rounded highlight on hover and press.
struct HeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HeaderButtonBody(configuration: configuration)
    }

    private struct HeaderButtonBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 6)
                .frame(minWidth: 26, minHeight: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : hovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}
