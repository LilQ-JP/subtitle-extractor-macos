import AppKit
import AVFoundation
import CoreImage
import CoreText
import Foundation

enum SubtitleUtilities {
    enum VideoAspectProfile {
        case landscape
        case square
        case portrait
    }

    static func availableFontNames() -> [String] {
        var fontNames = Set(NSFontManager.shared.availableFonts)
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        if let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] {
            for descriptor in descriptors {
                if let postScript = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
                   !postScript.isEmpty {
                    fontNames.insert(postScript)
                }
                if let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String,
                   !family.isEmpty {
                    fontNames.insert(family)
                }
                if let displayName = CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String,
                   !displayName.isEmpty {
                    fontNames.insert(displayName)
                }
            }
        }

        return Array(fontNames).sorted { lhs, rhs in
            let leftScore = fontPriority(lhs)
            let rightScore = fontPriority(rhs)
            if leftScore != rightScore {
                return leftScore > rightScore
            }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    static func videoAspectProfile(for size: CGSize) -> VideoAspectProfile {
        guard size.width > 0, size.height > 0 else {
            return .landscape
        }

        let ratio = size.width / size.height
        if ratio < 0.9 {
            return .portrait
        }
        if ratio <= 1.2 {
            return .square
        }
        return .landscape
    }

    static func defaultSubtitleRegion(for size: CGSize) -> NormalizedRect {
        switch videoAspectProfile(for: size) {
        case .landscape:
            return .defaultSubtitleArea
        case .square:
            return NormalizedRect(x: 0.06, y: 0.72, width: 0.88, height: 0.20)
        case .portrait:
            return NormalizedRect(x: 0.05, y: 0.70, width: 0.90, height: 0.22)
        }
    }

    static func defaultOverlayVideoRect(for size: CGSize) -> NormalizedRect {
        switch videoAspectProfile(for: size) {
        case .landscape:
            return NormalizedRect(x: 0.08, y: 0.08, width: 0.84, height: 0.72)
        case .square:
            return NormalizedRect(x: 0.06, y: 0.06, width: 0.88, height: 0.76)
        case .portrait:
            return NormalizedRect(x: 0.05, y: 0.05, width: 0.90, height: 0.78)
        }
    }

    static func defaultSubtitleLayoutRect(for size: CGSize, wrapWidthRatio: Double) -> NormalizedRect {
        switch videoAspectProfile(for: size) {
        case .landscape:
            return NormalizedRect(
                x: max(0.025, (1.0 - wrapWidthRatio) / 2.0),
                y: 0.74,
                width: min(max(wrapWidthRatio, 0.35), 0.95),
                height: 0.18
            ).clamped()
        case .square:
            let width = min(max(wrapWidthRatio, 0.72), 0.94)
            return NormalizedRect(
                x: max(0.03, (1.0 - width) / 2.0),
                y: 0.76,
                width: width,
                height: 0.16
            ).clamped()
        case .portrait:
            let width = min(max(wrapWidthRatio, 0.82), 0.94)
            return NormalizedRect(
                x: max(0.03, (1.0 - width) / 2.0),
                y: 0.76,
                width: width,
                height: 0.17
            ).clamped()
        }
    }

    static func subtitleFont(named fontName: String, size: CGFloat) -> NSFont {
        if let font = NSFont(name: fontName, size: size) {
            return font
        }
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: fontName,
            .name: fontName,
        ])
        if let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        let ctFont = CTFontCreateWithName(fontName as CFString, size, nil)
        let resolvedName = CTFontCopyPostScriptName(ctFont) as String
        if let font = NSFont(name: resolvedName, size: size) {
            return font
        }
        if let font = NSFont(name: "Hiragino Sans", size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: .medium)
    }

    static func fontFileURL(named fontName: String) -> URL? {
        if let font = NSFont(name: fontName, size: 14) {
            let descriptor = CTFontCopyFontDescriptor(font as CTFont)
            if let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL {
                return url
            }
        }

        let descriptor = CTFontDescriptorCreateWithNameAndSize(fontName as CFString, 14)
        return CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL
    }

    static func fontMatches(name: String, query: String) -> Bool {
        searchMatches(text: name, query: query)
    }

    static func searchMatches(text: String, query: String) -> Bool {
        let normalizedQuery = normalizedSearchToken(query)
        guard !normalizedQuery.isEmpty else {
            return true
        }
        return normalizedSearchToken(text).contains(normalizedQuery)
    }

    static func executablePath(named command: String) -> String? {
        let fileManager = FileManager.default
        let environmentPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let commonPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]

        let candidates = Array(Set(environmentPaths + commonPaths)).map {
            URL(fileURLWithPath: $0).appendingPathComponent(command).path
        }

        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    static func srtTimestamp(_ seconds: Double) -> String {
        let safe = max(0.0, seconds)
        let hours = Int(safe / 3600.0)
        let minutes = Int((safe.truncatingRemainder(dividingBy: 3600.0)) / 60.0)
        let secs = Int(safe.truncatingRemainder(dividingBy: 60.0))
        var milliseconds = Int(((safe - floor(safe)) * 1000.0).rounded())
        var adjustedSeconds = secs
        var adjustedMinutes = minutes
        var adjustedHours = hours

        if milliseconds >= 1000 {
            milliseconds -= 1000
            adjustedSeconds += 1
        }
        if adjustedSeconds >= 60 {
            adjustedSeconds -= 60
            adjustedMinutes += 1
        }
        if adjustedMinutes >= 60 {
            adjustedMinutes -= 60
            adjustedHours += 1
        }

        return String(format: "%02d:%02d:%02d,%03d", adjustedHours, adjustedMinutes, adjustedSeconds, milliseconds)
    }

    static func compactTimestamp(_ seconds: Double) -> String {
        let safe = max(0.0, seconds)
        let hours = Int(safe / 3600.0)
        let minutes = Int((safe.truncatingRemainder(dividingBy: 3600.0)) / 60.0)
        let secs = safe.truncatingRemainder(dividingBy: 60.0)
        return String(format: "%02d:%02d:%05.2f", hours, minutes, secs)
    }

    static func compactDuration(_ seconds: Double) -> String {
        let safe = max(0.0, seconds)
        let totalSeconds = Int(safe.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    static func parseTimecode(_ rawValue: String) -> Double? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        if let seconds = Double(value) {
            return max(0.0, seconds)
        }

        let sanitized = value.replacingOccurrences(of: ",", with: ".")
        let parts = sanitized.split(separator: ":").map(String.init)
        guard !parts.isEmpty else {
            return nil
        }

        if parts.count == 2,
           let minutes = Double(parts[0]),
           let seconds = Double(parts[1]) {
            return max(0.0, minutes * 60.0 + seconds)
        }

        if parts.count == 3,
           let hours = Double(parts[0]),
           let minutes = Double(parts[1]),
           let seconds = Double(parts[2]) {
            return max(0.0, hours * 3600.0 + minutes * 60.0 + seconds)
        }

        return nil
    }

    static func parseSRT(contents: String) -> [SubtitleItem] {
        let normalized = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let blocks = normalized.components(separatedBy: "\n\n")
        var subtitles: [SubtitleItem] = []

        for block in blocks {
            let rawLines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard rawLines.count >= 2 else {
                continue
            }

            let timeLineIndex = rawLines[0].contains("-->") ? 0 : 1
            guard rawLines.indices.contains(timeLineIndex) else {
                continue
            }

            let timeParts = rawLines[timeLineIndex].components(separatedBy: "-->")
            guard timeParts.count == 2,
                  let start = parseTimecode(timeParts[0]),
                  let end = parseTimecode(timeParts[1]) else {
                continue
            }

            let textLines = Array(rawLines.dropFirst(timeLineIndex + 1))
            let text = textLines.joined(separator: "\n")
            guard !text.isEmpty else {
                continue
            }

            subtitles.append(
                SubtitleItem(
                    index: subtitles.count + 1,
                    startTime: start,
                    endTime: end,
                    text: text
                )
            )
        }

        return subtitles
    }

    static func parseSRT(url: URL) throws -> [SubtitleItem] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return parseSRT(contents: contents)
    }

    static func subtitle(containing time: Double, in subtitles: [SubtitleItem], epsilon: Double = 0.02) -> SubtitleItem? {
        guard !subtitles.isEmpty else {
            return nil
        }

        let safeTime = max(0.0, time)
        return subtitles.first { subtitle in
            safeTime >= max(0.0, subtitle.startTime - epsilon) && safeTime < subtitle.endTime + epsilon
        }
    }

    static func normalizeSubtitles(
        _ subtitles: [SubtitleItem],
        minDuration: Double,
        maxDuration: Double,
        timelineEnd: Double?
    ) -> [SubtitleItem] {
        guard !subtitles.isEmpty else {
            return subtitles
        }

        let epsilon = 0.01
        var previousEnd = 0.0
        var normalized = subtitles.sorted {
            if $0.startTime == $1.startTime {
                if $0.endTime == $1.endTime {
                    return $0.index < $1.index
                }
                return $0.endTime < $1.endTime
            }
            return $0.startTime < $1.startTime
        }

        for index in normalized.indices {
            var subtitle = normalized[index]
            subtitle.startTime = max(0.0, subtitle.startTime, index > 0 ? previousEnd : 0.0)

            if let timelineEnd {
                subtitle.startTime = min(subtitle.startTime, max(0.0, timelineEnd - epsilon))
            }

            subtitle.endTime = max(subtitle.startTime + epsilon, subtitle.endTime)

            if maxDuration > 0 {
                subtitle.endTime = min(subtitle.endTime, subtitle.startTime + maxDuration)
            }

            var nextStart: Double?
            if normalized.indices.contains(index + 1) {
                nextStart = max(0.0, normalized[index + 1].startTime)
                nextStart = max(nextStart ?? 0.0, subtitle.startTime + epsilon)
            } else if let timelineEnd {
                nextStart = max(subtitle.startTime + epsilon, timelineEnd)
            }

            if minDuration > 0 {
                var desiredEnd = subtitle.startTime + minDuration
                if let nextStart {
                    desiredEnd = min(desiredEnd, nextStart - epsilon)
                }
                subtitle.endTime = max(subtitle.endTime, max(subtitle.startTime + epsilon, desiredEnd))
            }

            if let nextStart {
                let bridgedEnd: Double
                if maxDuration > 0 {
                    bridgedEnd = min(nextStart - epsilon, subtitle.startTime + maxDuration)
                } else {
                    bridgedEnd = nextStart - epsilon
                }
                subtitle.endTime = max(subtitle.endTime, max(subtitle.startTime + epsilon, bridgedEnd))
            } else if let timelineEnd {
                let trailingEnd: Double
                if maxDuration > 0 {
                    trailingEnd = min(timelineEnd, subtitle.startTime + maxDuration)
                } else {
                    trailingEnd = timelineEnd
                }
                subtitle.endTime = max(subtitle.endTime, max(subtitle.startTime + epsilon, trailingEnd))
            }

            if let nextStart {
                subtitle.endTime = min(subtitle.endTime, max(subtitle.startTime + epsilon, nextStart - epsilon))
            }

            if let timelineEnd {
                subtitle.endTime = min(subtitle.endTime, timelineEnd)
            }

            if subtitle.endTime <= subtitle.startTime {
                subtitle.endTime = subtitle.startTime + epsilon
            }

            subtitle.index = index + 1
            previousEnd = subtitle.endTime
            normalized[index] = subtitle
        }

        return normalized
    }

    static func measureTextWidth(_ text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else {
            return 0.0
        }
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    static func wrapText(
        _ text: String,
        maxWidth: CGFloat,
        font: NSFont,
        timingMode: WrapTimingMode = .balanced,
        preferredLineCount: Int = 0
    ) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty, maxWidth > 0 else {
            return normalized
        }

        let softWidth = preferredWrapWidth(
            for: normalized,
            hardWidth: maxWidth,
            font: font,
            timingMode: timingMode,
            preferredLineCount: preferredLineCount
        )

        func splitLongToken(_ token: String) -> [String] {
            var parts: [String] = []
            var current = ""
            for character in token {
                let candidate = current + String(character)
                if !current.isEmpty && measureTextWidth(candidate, font: font) > maxWidth {
                    parts.append(current)
                    current = String(character)
                } else {
                    current = candidate
                }
            }
            if !current.isEmpty {
                parts.append(current)
            }
            return parts
        }

        func isSpaceSeparated(_ line: String) -> Bool {
            let asciiCount = line.unicodeScalars.filter { $0.value < 128 }.count
            return line.contains(" ") && Double(asciiCount) >= Double(line.count) * 0.45
        }

        var wrappedLines: [String] = []

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if wrappedLines.last != "" {
                    wrappedLines.append("")
                }
                continue
            }

            if measureTextWidth(line, font: font) <= softWidth {
                wrappedLines.append(line)
                continue
            }

            if isSpaceSeparated(line) {
                var current = ""
                for word in line.split(separator: " ").map(String.init) {
                    if measureTextWidth(word, font: font) > maxWidth {
                        if !current.isEmpty {
                            wrappedLines.append(current)
                            current = ""
                        }
                        let pieces = splitLongToken(word)
                        wrappedLines.append(contentsOf: pieces.dropLast())
                        current = pieces.last ?? ""
                        continue
                    }

                    let candidate = current.isEmpty ? word : "\(current) \(word)"
                    if !current.isEmpty && measureTextWidth(candidate, font: font) > softWidth {
                        wrappedLines.append(current)
                        current = word
                    } else {
                        current = candidate
                    }
                }

                if !current.isEmpty {
                    wrappedLines.append(current)
                }
                continue
            }

            var current = ""
            for character in line {
                let candidate = current + String(character)
                if !current.isEmpty && measureTextWidth(candidate, font: font) > softWidth {
                    wrappedLines.append(current)
                    current = String(character)
                } else {
                    current = candidate
                }
            }
            if !current.isEmpty {
                wrappedLines.append(current)
            }
        }

        return wrappedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func previewWrappedText(
        for subtitle: SubtitleItem?,
        mode: ExportTextMode,
        videoWidth: Int?,
        wrapWidthRatio: Double,
        fontSize: CGFloat,
        fontName: String = "Hiragino Sans",
        timingMode: WrapTimingMode = .balanced,
        preferredLineCount: Int = 0
    ) -> String {
        guard let subtitle else {
            return ""
        }

        let source = if mode == .translated && !subtitle.translated.isEmpty {
            subtitle.translated
        } else {
            subtitle.text
        }

        let font = subtitleFont(named: fontName, size: fontSize)
        let width = max(120.0, CGFloat(videoWidth ?? 1920) * CGFloat(min(max(wrapWidthRatio, 0.3), 0.95)))
        return wrapText(
            source,
            maxWidth: width,
            font: font,
            timingMode: timingMode,
            preferredLineCount: preferredLineCount
        )
    }

    static func fitSubtitleLayout(
        text: String,
        regionSize: CGSize,
        fontName: String,
        preferredFontSize: CGFloat,
        outlineWidth: CGFloat,
        timingMode: WrapTimingMode = .balanced,
        preferredLineCount: Int = 0
    ) -> FittedSubtitleLayout {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return .empty
        }

        let safeRegion = CGSize(
            width: max(48.0, regionSize.width),
            height: max(18.0, regionSize.height)
        )

        let minimumFontSize: CGFloat = 3.0
        let initialFontSize = max(minimumFontSize, preferredFontSize)
        var fontSize = min(initialFontSize, max(initialFontSize, safeRegion.height))
        var bestLayout = FittedSubtitleLayout(
            text: normalized,
            fontSize: Double(fontSize),
            outlineWidth: Double(min(outlineWidth, max(0.0, fontSize * 0.18)))
        )

        while fontSize >= minimumFontSize {
            let font = subtitleFont(named: fontName, size: fontSize)
            let effectiveOutline = min(outlineWidth, max(0.0, fontSize * 0.18))
            let horizontalInset = max(8.0, font.pointSize * 0.28)
            let verticalInset = max(4.0, font.pointSize * 0.14)
            let availableSize = CGSize(
                width: max(20.0, safeRegion.width - horizontalInset * 2.0),
                height: max(8.0, safeRegion.height - verticalInset * 2.0)
            )

            let wrappedText = wrapText(
                normalized,
                maxWidth: availableSize.width,
                font: font,
                timingMode: timingMode,
                preferredLineCount: preferredLineCount
            )
            let measuredSize = measureSubtitleText(
                wrappedText,
                fontName: fontName,
                fontSize: fontSize,
                outlineWidth: effectiveOutline,
                maxSize: availableSize
            )
            let lineCount = lineCount(of: wrappedText)

            bestLayout = FittedSubtitleLayout(
                text: wrappedText,
                fontSize: Double(fontSize),
                outlineWidth: Double(effectiveOutline)
            )

            if measuredSize.width <= availableSize.width + 0.5,
               measuredSize.height <= availableSize.height + 0.5,
               (preferredLineCount <= 1 || lineCount <= preferredLineCount) {
                return bestLayout
            }

            fontSize -= fontSize > 12.0 ? 1.0 : 0.5
        }

        return bestLayout
    }

    static func lineCount(of text: String) -> Int {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return 0
        }
        return normalized.components(separatedBy: "\n").count
    }

    private static func preferredWrapWidth(
        for normalizedText: String,
        hardWidth: CGFloat,
        font: NSFont,
        timingMode: WrapTimingMode,
        preferredLineCount: Int
    ) -> CGFloat {
        var targetWidth = hardWidth * CGFloat(timingMode.fillRatio)
        if preferredLineCount > 1 {
            let flattened = normalizedText
                .components(separatedBy: .newlines)
                .joined(separator: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let totalWidth = measureTextWidth(flattened, font: font)
            if totalWidth > 0 {
                let approximateLineWidth = (totalWidth / CGFloat(preferredLineCount)) * 1.08
                targetWidth = min(targetWidth, approximateLineWidth)
            }
        }
        let minimumWidth = min(hardWidth, max(48.0, hardWidth * 0.45))
        return min(hardWidth, max(minimumWidth, targetWidth))
    }

    static func aspectFitRect(contentSize: CGSize, in bounds: CGRect) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let scale = min(bounds.width / contentSize.width, bounds.height / contentSize.height)
        let fittedSize = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
        let origin = CGPoint(
            x: bounds.midX - fittedSize.width / 2.0,
            y: bounds.midY - fittedSize.height / 2.0
        )
        return CGRect(origin: origin, size: fittedSize)
    }

    static func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    static func subtitleImage(
        text: String,
        size: CGSize,
        fontName: String,
        fontSize: CGFloat,
        outlineWidth: CGFloat,
        style: CaptionVisualStyle = .classic
    ) -> CGImage? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, size.width > 4, size.height > 4 else {
            return nil
        }

        let image = NSImage(size: size)
        image.lockFocusFlipped(true)
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let font = subtitleFont(named: fontName, size: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        let fillAttributed = NSAttributedString(
            string: normalized,
            attributes: [
                .font: font,
                .foregroundColor: style.textColor.nsColor,
                .paragraphStyle: paragraphStyle,
            ]
        )

        let strokeAttributed = NSAttributedString(
            string: normalized,
            attributes: [
                .font: font,
                .strokeColor: style.outlineColor.nsColor,
                .foregroundColor: style.outlineColor.nsColor,
                .strokeWidth: max(0.0, style.usesOutline ? outlineWidth * 2.0 : 0.0),
                .paragraphStyle: paragraphStyle,
            ]
        )
        let insetX = max(8.0, font.pointSize * 0.28)
        let insetY = max(4.0, font.pointSize * 0.14)
        let availableRect = CGRect(
            x: insetX,
            y: insetY,
            width: max(1.0, size.width - insetX * 2.0),
            height: max(1.0, size.height - insetY * 2.0)
        )

        let textBounds = fillAttributed.boundingRect(
            with: availableRect.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawRect = CGRect(
            x: availableRect.minX,
            y: max(availableRect.minY, availableRect.minY + (availableRect.height - textBounds.height) / 2.0),
            width: availableRect.width,
            height: min(availableRect.height, ceil(textBounds.height) + insetY)
        )

        let backgroundPaddingX = max(14.0, font.pointSize * 0.36)
        let backgroundPaddingY = max(6.0, font.pointSize * 0.20)
        let backgroundRect = CGRect(
            x: max(availableRect.minX, drawRect.midX - min(drawRect.width, textBounds.width + backgroundPaddingX * 2.0) / 2.0),
            y: max(availableRect.minY, drawRect.minY - backgroundPaddingY * 0.5),
            width: min(drawRect.width, max(textBounds.width + backgroundPaddingX * 2.0, font.pointSize * 3.2)),
            height: min(availableRect.height, textBounds.height + backgroundPaddingY * 2.0)
        ).integral

        if style.usesBackground {
            let backgroundPath = NSBezierPath(
                roundedRect: backgroundRect,
                xRadius: max(6.0, style.backgroundCornerRadius),
                yRadius: max(6.0, style.backgroundCornerRadius)
            )
            style.backgroundColor.nsColor.setFill()
            backgroundPath.fill()
        }

        if style.usesOutline, outlineWidth > 0 {
            strokeAttributed.draw(
                with: drawRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
        }

        if style.usesShadow {
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = style.shadowColor.nsColor
            shadow.shadowBlurRadius = max(1.0, font.pointSize * 0.12)
            shadow.shadowOffset = CGSize(width: 0, height: -1)
            shadow.set()
            fillAttributed.draw(
                with: drawRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            NSGraphicsContext.current?.restoreGraphicsState()
        } else {
            fillAttributed.draw(
                with: drawRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
        }

        return NSGraphicsContext.current?.cgContext.makeImage()
    }

    static func additionalSubtitleBannerImage(
        text: String,
        size: CGSize,
        fontName: String,
        fontSize: CGFloat,
        backgroundOpacity: CGFloat
    ) -> CGImage? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, size.width > 8, size.height > 8 else {
            return nil
        }

        let image = NSImage(size: size)
        image.lockFocusFlipped(true)
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let font = subtitleFont(named: fontName, size: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributed = NSAttributedString(
            string: normalized,
            attributes: [
                .font: font,
                .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 0.98),
                .paragraphStyle: paragraphStyle,
            ]
        )

        let outerInsetX = max(10.0, size.width * 0.018)
        let outerInsetY = max(4.0, size.height * 0.08)
        let maxBannerRect = CGRect(
            x: outerInsetX,
            y: outerInsetY,
            width: max(1.0, size.width - outerInsetX * 2.0),
            height: max(1.0, size.height - outerInsetY * 2.0)
        )
        let textInsetX = max(18.0, font.pointSize * 0.9)
        let textInsetY = max(8.0, font.pointSize * 0.34)
        let textMeasureRect = maxBannerRect.insetBy(dx: textInsetX, dy: textInsetY)
        let textBounds = attributed.boundingRect(
            with: textMeasureRect.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).integral

        let minimumBannerWidth = min(
            maxBannerRect.width,
            max(font.pointSize * 4.0, maxBannerRect.width * 0.58)
        )
        let minimumBannerHeight = min(
            maxBannerRect.height,
            max(font.pointSize * 2.0, maxBannerRect.height * 0.76)
        )
        let bannerWidth = min(
            maxBannerRect.width,
            max(textBounds.width + textInsetX * 2.0, minimumBannerWidth)
        )
        let bannerHeight = min(
            maxBannerRect.height,
            max(textBounds.height + textInsetY * 2.0, minimumBannerHeight)
        )
        let bannerRect = CGRect(
            x: maxBannerRect.midX - bannerWidth / 2.0,
            y: maxBannerRect.midY - bannerHeight / 2.0,
            width: bannerWidth,
            height: bannerHeight
        ).integral

        let bannerPath = NSBezierPath(
            roundedRect: bannerRect,
            xRadius: min(18.0, bannerRect.height * 0.28),
            yRadius: min(18.0, bannerRect.height * 0.28)
        )
        NSColor(
            calibratedRed: 0.95,
            green: 0.98,
            blue: 1.0,
            alpha: min(max(backgroundOpacity, 0.18), 0.98)
        ).setFill()
        bannerPath.fill()

        NSColor(calibratedWhite: 1.0, alpha: 0.82).setStroke()
        bannerPath.lineWidth = max(1.0, font.pointSize * 0.05)
        bannerPath.stroke()

        let drawRect = bannerRect.insetBy(dx: textInsetX, dy: textInsetY)

        NSGraphicsContext.current?.cgContext.setShadow(
            offset: CGSize(width: 0, height: 1),
            blur: 3,
            color: NSColor.black.withAlphaComponent(0.10).cgColor
        )
        attributed.draw(
            with: drawRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

        return NSGraphicsContext.current?.cgContext.makeImage()
    }

    static func measureSubtitleText(
        _ text: String,
        fontName: String,
        fontSize: CGFloat,
        outlineWidth: CGFloat,
        maxSize: CGSize
    ) -> CGSize {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return .zero
        }

        let font = subtitleFont(named: fontName, size: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributed = NSAttributedString(
            string: normalized,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle,
            ]
        )

        let measured = attributed.boundingRect(
            with: CGSize(width: maxSize.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).integral

        let extraPadding = ceil(max(0.0, outlineWidth) * 2.0)
        return CGSize(width: measured.width + extraPadding, height: measured.height + extraPadding)
    }

    static func detectChromaKeyColor(in image: NSImage) -> RGBColor? {
        guard let cgImage = cgImage(from: image) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            return nil
        }

        let sampleRect = CGRect(
            x: CGFloat(width) * 0.25,
            y: CGFloat(height) * 0.25,
            width: CGFloat(width) * 0.5,
            height: CGFloat(height) * 0.5
        ).integral

        guard let context = bitmapContext(width: width, height: height) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else {
            return nil
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var redTotal = 0.0
        var greenTotal = 0.0
        var blueTotal = 0.0
        var count = 0.0

        for y in Int(sampleRect.minY) ..< Int(sampleRect.maxY) {
            for x in Int(sampleRect.minX) ..< Int(sampleRect.maxX) {
                let offset = (y * width + x) * 4
                let alpha = Double(pixels[offset + 3]) / 255.0
                guard alpha > 0.01 else {
                    continue
                }

                let red = Double(pixels[offset]) / 255.0
                let green = Double(pixels[offset + 1]) / 255.0
                let blue = Double(pixels[offset + 2]) / 255.0
                redTotal += red
                greenTotal += green
                blueTotal += blue
                count += 1.0
            }
        }

        guard count > 0 else {
            return nil
        }

        return RGBColor(
            red: redTotal / count,
            green: greenTotal / count,
            blue: blueTotal / count
        )
    }

    static func processOverlayImage(
        _ image: NSImage,
        keyColor: RGBColor,
        tolerance: Double,
        softness: Double
    ) -> OverlayProcessingResult {
        guard let cgImage = cgImage(from: image) else {
            return OverlayProcessingResult(
                processedTIFFData: image.tiffRepresentation,
                transparentRect: nil,
                detectedKeyColor: keyColor
            )
        }

        let width = cgImage.width
        let height = cgImage.height

        guard let context = bitmapContext(width: width, height: height) else {
            return OverlayProcessingResult(
                processedTIFFData: image.tiffRepresentation,
                transparentRect: nil,
                detectedKeyColor: keyColor
            )
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else {
            return OverlayProcessingResult(
                processedTIFFData: image.tiffRepresentation,
                transparentRect: nil,
                detectedKeyColor: keyColor
            )
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let safeTolerance = max(0.0, min(tolerance, 1.5))
        let safeSoftness = max(0.001, min(softness, 1.5))
        let keyRed = keyColor.red
        let keyGreen = keyColor.green
        let keyBlue = keyColor.blue

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var transparentFound = false

        for y in 0 ..< height {
            for x in 0 ..< width {
                let offset = (y * width + x) * 4
                let red = Double(pixels[offset]) / 255.0
                let green = Double(pixels[offset + 1]) / 255.0
                let blue = Double(pixels[offset + 2]) / 255.0
                let originalAlpha = Double(pixels[offset + 3]) / 255.0

                let distance = sqrt(
                    pow(red - keyRed, 2) +
                        pow(green - keyGreen, 2) +
                        pow(blue - keyBlue, 2)
                )

                let alphaFactor: Double
                if distance <= safeTolerance {
                    alphaFactor = 0.0
                } else if distance >= safeTolerance + safeSoftness {
                    alphaFactor = 1.0
                } else {
                    alphaFactor = (distance - safeTolerance) / safeSoftness
                }

                let alpha = max(0.0, min(1.0, originalAlpha * alphaFactor))
                let premultipliedScale = originalAlpha > 0.001 ? alpha / originalAlpha : 0.0
                let cleanedRed = red * premultipliedScale
                let cleanedGreen = green * premultipliedScale
                let cleanedBlue = blue * premultipliedScale

                pixels[offset] = UInt8((max(0.0, min(1.0, cleanedRed)) * 255.0).rounded())
                pixels[offset + 1] = UInt8((max(0.0, min(1.0, cleanedGreen)) * 255.0).rounded())
                pixels[offset + 2] = UInt8((max(0.0, min(1.0, cleanedBlue)) * 255.0).rounded())
                pixels[offset + 3] = UInt8((alpha * 255.0).rounded())

                if alpha < 0.03 {
                    transparentFound = true
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        let processedImage: NSImage?
        if let processedCGImage = context.makeImage() {
            processedImage = NSImage(
                cgImage: processedCGImage,
                size: NSSize(width: processedCGImage.width, height: processedCGImage.height)
            )
        } else {
            processedImage = image
        }

        let transparentRect: NormalizedRect?
        if transparentFound, maxX > minX, maxY > minY {
            transparentRect = NormalizedRect(
                x: Double(minX) / Double(width),
                y: Double(minY) / Double(height),
                width: Double(maxX - minX + 1) / Double(width),
                height: Double(maxY - minY + 1) / Double(height)
            ).clamped()
        } else {
            transparentRect = nil
        }

        return OverlayProcessingResult(
            processedTIFFData: processedImage?.tiffRepresentation ?? image.tiffRepresentation,
            transparentRect: transparentRect,
            detectedKeyColor: keyColor
        )
    }

    static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func bitmapContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
    }

    private static func fontPriority(_ fontName: String) -> Int {
        let normalized = fontName.lowercased()
        let preferredTokens = [
            "hiragino",
            "hira",
            "yu",
            "gothic",
            "mincho",
            "maru",
            "tsukushi",
            "klee",
            "osaka",
            "bizud",
            "sawarabi",
            "noto sans cjk",
            "noto serif cjk",
        ]

        for (index, token) in preferredTokens.enumerated() where normalized.contains(token) {
            return preferredTokens.count - index
        }
        return 0
    }

    private static func normalizedSearchToken(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9ぁ-んァ-ン一-龥]", with: "", options: .regularExpression)
    }
}

enum VideoLoader {
    private static let subtitleCIContext = CIContext(options: nil)

    static func load(url: URL) async throws -> LoadedVideoAsset {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw NSError(
                domain: "CaptionStudio",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "動画トラックを取得できませんでした。"]
            )
        }

        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let durationValue = try await asset.load(.duration)
        let transformed = naturalSize.applying(preferredTransform)
        let width = Int(abs(transformed.width).rounded())
        let height = Int(abs(transformed.height).rounded())
        let fps = nominalFrameRate > 0 ? Double(nominalFrameRate) : 30.0
        let duration = durationValue.seconds.isFinite ? max(0.0, durationValue.seconds) : 0.0

        let metadata = VideoMetadata(
            path: url.path,
            width: width,
            height: height,
            fps: fps,
            duration: duration
        )

        let previewTIFFData = previewImageData(for: asset, duration: duration)

        return LoadedVideoAsset(
            metadata: metadata,
            previewTIFFData: previewTIFFData
        )
    }

    static func framePreviewImage(url: URL, at time: Double) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let durationValue = try? await asset.load(.duration)
        let duration = durationValue?.seconds.isFinite == true ? max(0.0, durationValue?.seconds ?? 0.0) : 0.0
        guard let imageRef = frameImage(
            for: asset,
            seconds: min(max(time, 0.0), max(duration - 0.05, 0.0)),
            duration: duration
        ) else {
            return nil
        }
        return NSImage(cgImage: imageRef, size: NSSize(width: imageRef.width, height: imageRef.height))
    }

    static func subtitleCropImageBase64Samples(
        url: URL,
        range: ClosedRange<Double>,
        region: NormalizedRect,
        language: TranslationLanguage,
        maxFrames: Int = 4,
        progressHandler: ExtractionProgressHandlerBox? = nil
    ) async throws -> [String] {
        let asset = AVURLAsset(url: url)
        let durationValue = try? await asset.load(.duration)
        let duration = durationValue?.seconds.isFinite == true ? max(0.0, durationValue?.seconds ?? 0.0) : 0.0

        return try await Task.detached(priority: .userInitiated) {
            let clampedRegion = region.clamped()
            let total = max(1, maxFrames)
            let lowerBound = min(max(range.lowerBound, 0.0), duration)
            let upperBound = min(max(range.upperBound, lowerBound), duration)
            let effectiveUpperBound = max(lowerBound, upperBound - 0.05)
            var results: [String] = []

            for index in 0 ..< total {
                try Task.checkCancellation()

                let progress = total == 1 ? 0.5 : Double(index) / Double(total - 1)
                let seconds = lowerBound + (effectiveUpperBound - lowerBound) * progress
                let clampedSeconds = min(max(seconds, lowerBound), effectiveUpperBound)
                if let image = frameImage(for: asset, seconds: clampedSeconds, duration: duration),
                   let cropped = crop(image: image, region: clampedRegion) {
                    if let encoded = pngBase64(from: cropped) {
                        results.append(encoded)
                    }
                    if let enhanced = enhancedSubtitleImage(from: cropped, language: language),
                       let encodedEnhanced = pngBase64(from: enhanced) {
                        results.append(encodedEnhanced)
                    }
                }
                progressHandler?.report(
                    ExtractionProgress(
                        processed: index + 1,
                        total: total,
                        timestamp: clampedSeconds
                    )
                )
            }

            return Array(results.prefix(total))
        }.value
    }

    private static func previewImageData(for asset: AVURLAsset, duration: Double) -> Data? {
        let candidateSeconds = Array(
            Set([
                min(max(duration * 0.10, 0.0), max(duration - 0.05, 0.0)),
                0.0,
                min(0.5, max(duration - 0.05, 0.0)),
                min(max(duration * 0.5, 0.0), max(duration - 0.05, 0.0)),
            ])
        )
        for seconds in candidateSeconds {
            if let imageRef = frameImage(for: asset, seconds: seconds, duration: duration) {
                let image = NSImage(cgImage: imageRef, size: NSSize(width: imageRef.width, height: imageRef.height))
                if let data = image.tiffRepresentation {
                    return data
                }
            }
        }
        return nil
    }

    private static func frameImage(for asset: AVURLAsset, seconds: Double, duration: Double) -> CGImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1400, height: 900)
        let tolerance = CMTime(seconds: 0.10, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let safeDuration = duration.isFinite ? max(0.0, duration) : 0.0
        let candidates = NativeOCRExtractor.frameReadCandidateTimes(
            requestedTime: seconds,
            duration: safeDuration,
            frameDuration: 1.0 / 30.0
        )

        for candidate in candidates {
            let sampleTime = CMTime(seconds: candidate, preferredTimescale: 600)
            if let image = try? generator.copyCGImage(at: sampleTime, actualTime: nil) {
                return image
            }
        }
        return nil
    }

    private static func crop(image: CGImage, region: NormalizedRect) -> CGImage? {
        let padded = NormalizedRect(
            x: max(0.0, region.x - 0.015),
            y: max(0.0, region.y - 0.015),
            width: min(1.0 - max(0.0, region.x - 0.015), region.width + 0.03),
            height: min(1.0 - max(0.0, region.y - 0.015), region.height + 0.03)
        ).clamped()

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let cropRect = CGRect(
            x: max(0, min(width - 1, width * padded.x)),
            y: max(0, min(height - 1, height * padded.y)),
            width: max(1, min(width, width * padded.width)),
            height: max(1, min(height, height * padded.height))
        ).integral

        guard let cropped = image.cropping(to: cropRect) else {
            return nil
        }

        let targetWidth = max(cropped.width * 2, 720)
        let scale = CGFloat(targetWidth) / CGFloat(max(cropped.width, 1))
        let targetHeight = max(Int((CGFloat(cropped.height) * scale).rounded()), cropped.height)
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return cropped
        }

        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage() ?? cropped
    }

    private static func pngBase64(from image: CGImage) -> String? {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            return nil
        }
        return data.base64EncodedString()
    }

    private static func enhancedSubtitleImage(from image: CGImage, language: TranslationLanguage) -> CGImage? {
        guard language == .korean || language == .chinese || language == .english else {
            return nil
        }

        let ciImage = CIImage(cgImage: image)
        var output = ciImage.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: language == .english ? 1.8 : 1.65,
                kCIInputBrightnessKey: 0.02,
            ]
        )
        output = output.applyingFilter(
            "CISharpenLuminance",
            parameters: [
                kCIInputSharpnessKey: language == .english ? 0.85 : 0.7,
            ]
        )
        output = output.applyingFilter(
            "CIGammaAdjust",
            parameters: [
                "inputPower": language == .english ? 0.82 : 0.74,
            ]
        )

        return subtitleCIContext.createCGImage(output, from: output.extent.integral)
    }
}
