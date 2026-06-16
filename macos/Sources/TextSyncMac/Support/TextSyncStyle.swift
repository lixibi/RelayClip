import AppKit
import SwiftUI

extension Color {
    static let textSyncBrown = adaptiveColor(
        light: NSColor(calibratedRed: 0.44, green: 0.30, blue: 0.18, alpha: 1),
        dark: NSColor(calibratedRed: 0.93, green: 0.84, blue: 0.70, alpha: 1)
    )

    static let textSyncMuted = adaptiveColor(
        light: NSColor(calibratedRed: 0.54, green: 0.47, blue: 0.37, alpha: 1),
        dark: NSColor(calibratedRed: 0.72, green: 0.66, blue: 0.56, alpha: 1)
    )

    static let textSyncTeal = adaptiveColor(
        light: NSColor(calibratedRed: 0.10, green: 0.70, blue: 0.65, alpha: 1),
        dark: NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.78, alpha: 1)
    )

    static let textSyncGreen = adaptiveColor(
        light: NSColor(calibratedRed: 0.39, green: 0.66, blue: 0.22, alpha: 1),
        dark: NSColor(calibratedRed: 0.61, green: 0.84, blue: 0.36, alpha: 1)
    )

    static let textSyncWarning = adaptiveColor(
        light: NSColor(calibratedRed: 0.84, green: 0.52, blue: 0.10, alpha: 1),
        dark: NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.28, alpha: 1)
    )

    static let textSyncCream = adaptiveColor(
        light: NSColor(calibratedRed: 1.00, green: 0.96, blue: 0.84, alpha: 1),
        dark: NSColor(calibratedRed: 0.23, green: 0.18, blue: 0.12, alpha: 1)
    )

    static let textSyncPaper = adaptiveColor(
        light: NSColor(calibratedRed: 1.00, green: 0.99, blue: 0.95, alpha: 1),
        dark: NSColor(calibratedRed: 0.16, green: 0.15, blue: 0.12, alpha: 1)
    )

    static let textSyncLine = adaptiveColor(
        light: NSColor(calibratedRed: 0.82, green: 0.77, blue: 0.68, alpha: 1),
        dark: NSColor(calibratedRed: 0.36, green: 0.31, blue: 0.24, alpha: 1)
    )

    static let textSyncPanel = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.82),
        dark: NSColor(calibratedRed: 0.13, green: 0.12, blue: 0.10, alpha: 0.92)
    )

    static let textSyncPanelStroke = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.75),
        dark: NSColor(calibratedRed: 0.40, green: 0.34, blue: 0.26, alpha: 0.70)
    )

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }
}

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark ? darkColors : lightColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var lightColors: [Color] {
        [
            Color(red: 0.98, green: 0.97, blue: 0.92),
            Color(red: 0.89, green: 0.97, blue: 0.95),
            Color(red: 1.00, green: 0.94, blue: 0.86)
        ]
    }

    private var darkColors: [Color] {
        [
            Color(red: 0.11, green: 0.10, blue: 0.08),
            Color(red: 0.08, green: 0.16, blue: 0.15),
            Color(red: 0.16, green: 0.12, blue: 0.08)
        ]
    }
}

struct TextSyncPanelBackground: View {
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(tint)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.textSyncPanelStroke, lineWidth: 1)
            )
            .shadow(color: Color.textSyncBrown.opacity(0.10), radius: 18, x: 0, y: 8)
    }
}

struct TextSyncPillButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Capsule().fill(color))
            .shadow(color: color.opacity(0.24), radius: 0, x: 0, y: configuration.isPressed ? 1 : 3)
            .offset(y: configuration.isPressed ? 2 : 0)
    }
}

struct TextSyncInlineButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(color.opacity(configuration.isPressed ? 0.20 : 0.11)))
            .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 1))
    }
}

struct TextSyncIconButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 30, height: 28)
            .background(Capsule().fill(color.opacity(configuration.isPressed ? 0.20 : 0.10)))
            .overlay(Capsule().stroke(color.opacity(0.26), lineWidth: 1))
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}
