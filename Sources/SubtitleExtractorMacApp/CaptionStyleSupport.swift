import AppKit
import CaptionAppearanceBridge
import Foundation

private let captionEdgeStyleNone: Int = 1
private let captionEdgeStyleUniform: Int = 4
private let captionEdgeStyleDropShadow: Int = 5

struct SystemCaptionAppearance: Hashable, Sendable {
    var visualStyle: CaptionVisualStyle
    var preferredFontName: String?
}

enum CaptionStyleResolver {
    static func visualStyle(
        for preset: CaptionStylePreset,
        systemAppearance: SystemCaptionAppearance?
    ) -> CaptionVisualStyle {
        switch preset {
        case .classic:
            return .classic
        case .youtube:
            return .youtube
        case .systemAccessibility:
            return systemAppearance?.visualStyle ?? .youtube
        }
    }

    static func preferredFontName(
        for preset: CaptionStylePreset,
        systemAppearance: SystemCaptionAppearance?
    ) -> String? {
        guard preset == .systemAccessibility else {
            return nil
        }
        return systemAppearance?.preferredFontName
    }

    static func loadSystemAppearance() -> SystemCaptionAppearance? {
        let raw = SELoadSystemCaptionAppearance()
        guard raw.success else {
            return nil
        }

        let foreground = RGBAColor(
            red: clamp(raw.foregroundRed, fallback: 1.0),
            green: clamp(raw.foregroundGreen, fallback: 1.0),
            blue: clamp(raw.foregroundBlue, fallback: 1.0),
            alpha: clamp(raw.foregroundAlpha, fallback: 1.0)
        )

        let window = RGBAColor(
            red: clamp(raw.windowRed, fallback: 0.0),
            green: clamp(raw.windowGreen, fallback: 0.0),
            blue: clamp(raw.windowBlue, fallback: 0.0),
            alpha: clamp(raw.windowAlpha, fallback: 0.65)
        )

        let background = RGBAColor(
            red: clamp(raw.backgroundRed, fallback: window.red),
            green: clamp(raw.backgroundGreen, fallback: window.green),
            blue: clamp(raw.backgroundBlue, fallback: window.blue),
            alpha: clamp(raw.backgroundAlpha, fallback: window.alpha)
        )

        let preferredBackground = window.alpha > 0.05 ? window : background
        let edgeStyle = Int(raw.textEdgeStyle)
        let relativeScale = max(0.75, min(1.6, raw.relativeCharacterSize > 0 ? raw.relativeCharacterSize : 1.0))
        let fontName = withUnsafePointer(to: raw.fontName) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: raw.fontName)) {
                String(validatingCString: $0) ?? ""
            }
        }.trimmingCharacters(in: .whitespacesAndNewlines)

        let style = CaptionVisualStyle(
            textColor: foreground,
            outlineColor: .black,
            backgroundColor: preferredBackground,
            shadowColor: RGBAColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.32),
            usesBackground: preferredBackground.alpha > 0.05,
            usesOutline: edgeStyle == captionEdgeStyleUniform,
            usesShadow: edgeStyle == captionEdgeStyleDropShadow,
            backgroundCornerRadius: max(8.0, raw.windowCornerRadius),
            relativeScale: relativeScale
        )

        return SystemCaptionAppearance(
            visualStyle: style,
            preferredFontName: fontName.isEmpty ? nil : fontName
        )
    }

    private static func clamp(_ value: Double, fallback: Double) -> Double {
        if value.isNaN || value.isInfinite {
            return fallback
        }
        return min(max(value, 0.0), 1.0)
    }
}

extension RGBAColor {
    var nsColor: NSColor {
        NSColor(
            calibratedRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}
