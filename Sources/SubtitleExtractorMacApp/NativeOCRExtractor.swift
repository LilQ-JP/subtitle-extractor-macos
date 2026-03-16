import AVFoundation
import CoreImage
import Foundation
import Vision

enum NativeOCRExtractorError: LocalizedError {
    case unreadableVideoFrames

    var errorDescription: String? {
        switch self {
        case .unreadableVideoFrames:
            return "動画フレームを読み取れませんでした。動画が破損しているか、抽出範囲が極端に狭い可能性があります。"
        }
    }
}

struct NativeOCRExtractor {
    static let frameEpsilon = 1.0 / 600.0
    private static let ciContext = CIContext(options: nil)

    static func extract(
        videoURL: URL,
        region: NormalizedRect?,
        preferences: ProcessingPreferences,
        language: TranslationLanguage,
        progressHandler: ExtractionProgressHandlerBox? = nil
    ) async throws -> BackendExtractPayload {
        let loadedVideo = try await VideoLoader.load(url: videoURL)
        return try await Task.detached(priority: .userInitiated) {
            try extractSync(
                videoURL: videoURL,
                metadata: loadedVideo.metadata,
                region: region,
                preferences: preferences,
                language: language,
                progressHandler: progressHandler
            )
        }.value
    }

    static func mergeFrameTexts(
        _ frameTexts: [(time: Double, text: String)],
        sampleInterval: Double = 0.0,
        language: TranslationLanguage = .english
    ) -> [SubtitleItem] {
        guard !frameTexts.isEmpty else {
            return []
        }

        let timingPadding = sampleInterval > 0 ? min(sampleInterval / 2.0, 0.25) : 0.0
        let separationGapThreshold = sampleInterval > 0 ? max(sampleInterval * 1.6, 0.6) : 0.6
        let duplicateGapThreshold = sampleInterval > 0 ? max(sampleInterval * 1.1, 0.35) : 0.35
        var subtitles: [SubtitleItem] = []
        var currentText = ""
        var startTime = 0.0
        var endTime = 0.0

        for (timestamp, rawText) in frameTexts {
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }

            if currentText.isEmpty {
                currentText = text
                startTime = max(0.0, timestamp - timingPadding)
                endTime = timestamp + timingPadding
                continue
            }

            let gap = max(0.0, timestamp - endTime)
            if gap > separationGapThreshold {
                subtitles.append(
                    SubtitleItem(
                        index: subtitles.count + 1,
                        startTime: startTime,
                        endTime: endTime,
                        text: currentText
                    )
                )
                currentText = text
                startTime = max(0.0, timestamp - timingPadding)
                endTime = timestamp + timingPadding
                continue
            }

            if shouldMergeRecognizedTexts(currentText, text, language: language) {
                endTime = max(endTime, timestamp + timingPadding)
                if text.count >= currentText.count {
                    currentText = text
                }
            } else {
                subtitles.append(
                    SubtitleItem(
                        index: subtitles.count + 1,
                        startTime: startTime,
                        endTime: endTime,
                        text: currentText
                    )
                )
                currentText = text
                startTime = max(0.0, timestamp - timingPadding)
                endTime = timestamp + timingPadding
            }
        }

        if !currentText.isEmpty {
            subtitles.append(
                SubtitleItem(
                    index: subtitles.count + 1,
                    startTime: startTime,
                    endTime: endTime,
                    text: currentText
                )
            )
        }

        return mergeAdjacentDuplicateSubtitles(
            subtitles,
            maxGap: duplicateGapThreshold,
            language: language
        )
    }

    static func rerecognize(
        videoURL: URL,
        range: ClosedRange<Double>,
        region: NormalizedRect?,
        preferences: ProcessingPreferences,
        language: TranslationLanguage,
        progressHandler: ExtractionProgressHandlerBox? = nil
    ) async throws -> String {
        let loadedVideo = try await VideoLoader.load(url: videoURL)
        return try await Task.detached(priority: .userInitiated) {
            let frameTexts = try collectFrameTexts(
                videoURL: videoURL,
                metadata: loadedVideo.metadata,
                region: region,
                preferences: preferences,
                language: language,
                timeRange: range,
                progressHandler: progressHandler
            )
            return bestRecognizedText(from: frameTexts, language: language)
        }.value
    }

    private static func extractSync(
        videoURL: URL,
        metadata: VideoMetadata,
        region: NormalizedRect?,
        preferences: ProcessingPreferences,
        language: TranslationLanguage,
        progressHandler: ExtractionProgressHandlerBox? = nil
    ) throws -> BackendExtractPayload {
        let frameTexts = try collectFrameTexts(
            videoURL: videoURL,
            metadata: metadata,
            region: region,
            preferences: preferences,
            language: language,
            timeRange: 0.0 ... metadata.duration,
            progressHandler: progressHandler
        )

        return BackendExtractPayload(
            subtitles: mergeFrameTexts(
                frameTexts,
                sampleInterval: max(1.0 / max(preferences.fpsSample, 0.5), 0.1),
                language: language
            ),
            video: metadata
        )
    }

    static func sampleCount(duration: Double, sampleInterval: Double) -> Int {
        let effectiveDuration = max(duration - frameEpsilon, 0.0)
        return max(Int(floor(effectiveDuration / sampleInterval)) + 1, 1)
    }

    static func sampleTimestamp(for index: Int, sampleInterval: Double, duration: Double) -> Double {
        guard duration > 0 else {
            return 0.0
        }
        let effectiveDuration = max(duration - frameEpsilon, 0.0)
        return min(Double(index) * sampleInterval, effectiveDuration)
    }

    static func frameReadCandidateTimes(
        requestedTime: Double,
        duration: Double,
        frameDuration: Double
    ) -> [Double] {
        guard duration > 0 else {
            return [0.0]
        }

        let safeFrameDuration = max(frameDuration, frameEpsilon)
        let effectiveDuration = max(duration - frameEpsilon, 0.0)
        let clampedRequestedTime = min(max(requestedTime, 0.0), effectiveDuration)

        let offsets: [Double] = [
            0.0,
            safeFrameDuration,
            safeFrameDuration * 2.0,
            -safeFrameDuration,
            -safeFrameDuration * 2.0,
            0.05,
            -0.05,
            0.10,
            -0.10,
        ]

        var candidates: [Double] = []
        for offset in offsets {
            let candidate = min(max(clampedRequestedTime + offset, 0.0), effectiveDuration)
            if candidates.contains(where: { abs($0 - candidate) < frameEpsilon }) {
                continue
            }
            candidates.append(candidate)
        }
        return candidates
    }

    private static func sampleCount(
        startTime: Double,
        endTime: Double,
        sampleInterval: Double
    ) -> Int {
        let safeStart = max(0.0, startTime)
        let safeEnd = max(safeStart, endTime - frameEpsilon)
        return max(Int(floor((safeEnd - safeStart) / sampleInterval)) + 1, 1)
    }

    private static func sampleTimestamp(
        for index: Int,
        startTime: Double,
        endTime: Double,
        sampleInterval: Double
    ) -> Double {
        let safeStart = max(0.0, startTime)
        let safeEnd = max(safeStart, endTime - frameEpsilon)
        return min(safeStart + Double(index) * sampleInterval, safeEnd)
    }

    private static func collectFrameTexts(
        videoURL: URL,
        metadata: VideoMetadata,
        region: NormalizedRect?,
        preferences: ProcessingPreferences,
        language: TranslationLanguage,
        timeRange: ClosedRange<Double>,
        progressHandler: ExtractionProgressHandlerBox?
    ) throws -> [(time: Double, text: String)] {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let frameDuration = max(1.0 / max(metadata.fps, 1.0), frameEpsilon)
        let tolerance = CMTime(seconds: max(frameDuration * 2.0, 0.05), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let sampleInterval = max(1.0 / max(preferences.fpsSample, 0.5), 0.1)
        let startTime = max(0.0, min(timeRange.lowerBound, metadata.duration))
        let endTime = max(startTime, min(timeRange.upperBound, metadata.duration))
        let total = sampleCount(
            startTime: startTime,
            endTime: endTime,
            sampleInterval: sampleInterval
        )
        var frameTexts: [(time: Double, text: String)] = []
        var successfulFrameCount = 0
        var lastFrameReadError: Error?

        for index in 0 ..< total {
            try Task.checkCancellation()

            let timestamp = sampleTimestamp(
                for: index,
                startTime: startTime,
                endTime: endTime,
                sampleInterval: sampleInterval
            )
            do {
                let image = try copySampleImage(
                    with: generator,
                    requestedTime: timestamp,
                    duration: metadata.duration,
                    frameDuration: frameDuration
                )
                let cropped = crop(image: image, region: region)
                let recognized = try recognizeText(in: cropped, language: language)
                let normalized = sanitizeRecognizedText(recognized, language: language)
                successfulFrameCount += 1
                if !normalized.isEmpty {
                    frameTexts.append((time: timestamp, text: normalized))
                }
            } catch {
                lastFrameReadError = error
            }
            progressHandler?.report(
                ExtractionProgress(processed: index + 1, total: total, timestamp: timestamp)
            )
        }

        guard successfulFrameCount > 0 else {
            if let error = lastFrameReadError {
                let nsError = error as NSError
                if nsError.domain == AVFoundationErrorDomain && nsError.code == -11832 {
                    throw NativeOCRExtractorError.unreadableVideoFrames
                }
            }
            throw lastFrameReadError ?? NativeOCRExtractorError.unreadableVideoFrames
        }

        return frameTexts
    }

    private static func copySampleImage(
        with generator: AVAssetImageGenerator,
        requestedTime: Double,
        duration: Double,
        frameDuration: Double
    ) throws -> CGImage {
        let candidates = frameReadCandidateTimes(
            requestedTime: requestedTime,
            duration: duration,
            frameDuration: frameDuration
        )
        var lastError: Error?

        for candidate in candidates {
            do {
                let time = CMTime(seconds: candidate, preferredTimescale: 600)
                return try generator.copyCGImage(at: time, actualTime: nil)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NativeOCRExtractorError.unreadableVideoFrames
    }

    private static func bestRecognizedText(
        from frameTexts: [(time: Double, text: String)],
        language: TranslationLanguage
    ) -> String {
        let candidates = frameTexts
            .map(\.text)
            .map { sanitizeRecognizedText($0, language: language) }
            .filter { !$0.isEmpty }

        guard !candidates.isEmpty else {
            return ""
        }

        var groups: [(text: String, count: Int)] = []
        for candidate in candidates {
            if let index = groups.firstIndex(where: { group in
                let similarity = similarityScore(lhs: group.text, rhs: candidate)
                return similarity >= 0.72 || group.text.contains(candidate) || candidate.contains(group.text)
            }) {
                groups[index].count += 1
                if candidate.count >= groups[index].text.count {
                    groups[index].text = candidate
                }
            } else {
                groups.append((text: candidate, count: 1))
            }
        }

        return groups.max { lhs, rhs in
            let leftScore = Double(lhs.count) * 1.8 + Double(lhs.text.count) * 0.06 + scriptCoverageScore(for: lhs.text, language: language) * 4.0
            let rightScore = Double(rhs.count) * 1.8 + Double(rhs.text.count) * 0.06 + scriptCoverageScore(for: rhs.text, language: language) * 4.0
            return leftScore < rightScore
        }?.text ?? candidates[0]
    }

    private static func crop(image: CGImage, region: NormalizedRect?) -> CGImage {
        guard let region else {
            return image
        }

        let clamped = region.clamped()
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let cropRect = CGRect(
            x: max(0, min(width, width * clamped.x)),
            y: max(0, min(height, height * clamped.y)),
            width: max(1, min(width, width * clamped.width)),
            height: max(1, min(height, height * clamped.height))
        ).integral

        return image.cropping(to: cropRect) ?? image
    }

    private static func recognizeText(in image: CGImage, language: TranslationLanguage) throws -> String {
        let variants = preparedOCRImages(from: image, language: language)
        var bestCandidate: OCRCandidate?

        for variant in variants {
            let candidate = try recognizeTextCandidate(in: variant, language: language)
            if let currentBest = bestCandidate {
                if candidate.score > currentBest.score {
                    bestCandidate = candidate
                }
            } else {
                bestCandidate = candidate
            }
        }

        return bestCandidate?.text ?? ""
    }

    private static func recognitionLanguages(for language: TranslationLanguage) -> [String] {
        switch language {
        case .japanese:
            return ["ja-JP", "ja"]
        case .english:
            return ["en-US", "en-GB", "en"]
        case .chinese:
            return ["zh-Hans", "zh-Hant", "zh-CN", "zh-TW"]
        case .korean:
            return ["ko-KR", "ko"]
        }
    }

    private static func resolvedRecognitionLanguages(
        for language: TranslationLanguage,
        request: VNRecognizeTextRequest
    ) -> [String] {
        let preferred = recognitionLanguages(for: language)
        if #available(macOS 13.0, *),
           let supported = try? request.supportedRecognitionLanguages(),
           !supported.isEmpty
        {
            let filtered = preferred.filter(supported.contains)
            if !filtered.isEmpty {
                return filtered
            }
        }
        return preferred
    }

    private static func recognizeTextCandidate(
        in image: CGImage,
        language: TranslationLanguage
    ) throws -> OCRCandidate {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = usesLanguageCorrection(for: language)
        request.recognitionLanguages = resolvedRecognitionLanguages(for: language, request: request)
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = false
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = (request.results ?? [])
            .sorted { lhs, rhs in
                lhs.boundingBox.minY > rhs.boundingBox.minY
            }

        let candidates = observations.compactMap { observation in
            observation.topCandidates(1).first
        }
        let text = sanitizeRecognizedText(
            candidates
                .map(\.string)
                .joined(separator: "\n"),
            language: language
        )
        let confidence = candidates.isEmpty ? 0.0 : candidates.map(\.confidence).reduce(0, +) / Float(candidates.count)
        let scriptCoverage = scriptCoverageScore(for: text, language: language)
        let score = weightedOCRScore(
            confidence: Double(confidence),
            scriptCoverage: scriptCoverage,
            textLength: text.count,
            language: language
        )
        return OCRCandidate(
            text: text,
            averageConfidence: Double(confidence),
            scriptCoverage: scriptCoverage,
            score: score
        )
    }

    private static func usesLanguageCorrection(for language: TranslationLanguage) -> Bool {
        switch language {
        case .english:
            return true
        case .japanese, .chinese, .korean:
            return false
        }
    }

    private static func preparedOCRImages(
        from image: CGImage,
        language: TranslationLanguage
    ) -> [CGImage] {
        var variants: [CGImage] = [image]
        if let enhanced = makeEnhancedOCRImage(from: image, language: language) {
            variants.append(enhanced)
        }
        if let thresholded = makeThresholdedOCRImage(from: image, language: language) {
            variants.append(thresholded)
        }
        return variants
    }

    private static func makeEnhancedOCRImage(
        from image: CGImage,
        language: TranslationLanguage
    ) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let maxDimension = max(ciImage.extent.width, ciImage.extent.height)
        let scale = min(max(2.2, 1200.0 / max(maxDimension, 1.0)), 3.0)

        var output = ciImage.applyingFilter(
            "CILanczosScaleTransform",
            parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1.0,
            ]
        )
        output = output.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: contrastStrength(for: language),
                kCIInputBrightnessKey: 0.01,
            ]
        )
        output = output.applyingFilter(
            "CISharpenLuminance",
            parameters: [
                kCIInputSharpnessKey: sharpenStrength(for: language),
            ]
        )

        return ciContext.createCGImage(output, from: output.extent.integral)
    }

    private static func contrastStrength(for language: TranslationLanguage) -> Double {
        switch language {
        case .english:
            return 1.45
        case .chinese, .korean:
            return 1.35
        case .japanese:
            return 1.2
        }
    }

    private static func sharpenStrength(for language: TranslationLanguage) -> Double {
        switch language {
        case .english:
            return 0.75
        case .chinese, .korean:
            return 0.55
        case .japanese:
            return 0.4
        }
    }

    private static func makeThresholdedOCRImage(
        from image: CGImage,
        language: TranslationLanguage
    ) -> CGImage? {
        guard language == .korean || language == .chinese || language == .english else {
            return nil
        }

        let ciImage = CIImage(cgImage: image)
        let maxDimension = max(ciImage.extent.width, ciImage.extent.height)
        let scale = min(max(2.4, 1360.0 / max(maxDimension, 1.0)), 3.2)

        var output = ciImage.applyingFilter(
            "CILanczosScaleTransform",
            parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1.0,
            ]
        )
        output = output.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: language == .english ? 1.95 : 1.8,
                kCIInputBrightnessKey: 0.03,
            ]
        )
        output = output.applyingFilter(
            "CISharpenLuminance",
            parameters: [
                kCIInputSharpnessKey: language == .english ? 0.9 : 0.7,
            ]
        )
        output = output.applyingFilter(
            "CIGammaAdjust",
            parameters: [
                "inputPower": language == .english ? 0.78 : 0.7,
            ]
        )

        return ciContext.createCGImage(output, from: output.extent.integral)
    }

    private static func weightedOCRScore(
        confidence: Double,
        scriptCoverage: Double,
        textLength: Int,
        language: TranslationLanguage
    ) -> Double {
        switch language {
        case .korean, .chinese:
            return confidence * 0.52 + scriptCoverage * 0.43 + min(Double(textLength), 120.0) * 0.0025
        case .english:
            return confidence * 0.68 + scriptCoverage * 0.27 + min(Double(textLength), 120.0) * 0.0025
        case .japanese:
            return confidence * 0.7 + scriptCoverage * 0.25 + min(Double(textLength), 120.0) * 0.0025
        }
    }

    static func scriptCoverageScore(for text: String, language: TranslationLanguage) -> Double {
        let scalars = text.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar) &&
                !CharacterSet.punctuationCharacters.contains(scalar) &&
                !CharacterSet.symbols.contains(scalar)
        }

        guard !scalars.isEmpty else {
            return 0.0
        }

        let matchedCount = scalars.reduce(into: 0) { result, scalar in
            if matchesExpectedScript(scalar, language: language) {
                result += 1
            }
        }

        return Double(matchedCount) / Double(scalars.count)
    }

    private static func matchesExpectedScript(
        _ scalar: UnicodeScalar,
        language: TranslationLanguage
    ) -> Bool {
        let value = scalar.value
        switch language {
        case .english:
            return (value >= 0x41 && value <= 0x5A) || (value >= 0x61 && value <= 0x7A) || (value >= 0x30 && value <= 0x39)
        case .chinese:
            return (value >= 0x4E00 && value <= 0x9FFF) || (value >= 0x3400 && value <= 0x4DBF)
        case .korean:
            return (value >= 0xAC00 && value <= 0xD7AF) || (value >= 0x1100 && value <= 0x11FF) || (value >= 0x3130 && value <= 0x318F)
        case .japanese:
            return (value >= 0x3040 && value <= 0x30FF) || (value >= 0x4E00 && value <= 0x9FFF)
        }
    }

    static func sanitizeRecognizedText(_ text: String, language: TranslationLanguage) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { sanitizeRecognizedLine(String($0), language: language) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func sanitizeRecognizedLine(_ line: String, language: TranslationLanguage) -> String {
        let filtered = String(String.UnicodeScalarView(
            line.unicodeScalars.filter { scalar in
                shouldKeepScalar(scalar)
            }
        ))
        let collapsedSpaces = filtered.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let trimmed = collapsedSpaces.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        let normalized = normalizeRecognizedLine(trimmed, language: language)
        guard !normalized.isEmpty else {
            return ""
        }
        let meaningfulScalarCount = normalized.unicodeScalars.filter { scalar in
            matchesExpectedScript(scalar, language: language) || CharacterSet.decimalDigits.contains(scalar)
        }.count
        if meaningfulScalarCount == 0 && normalized.count <= 3 {
            return ""
        }
        return normalized
    }

    private static func normalizeRecognizedLine(_ line: String, language: TranslationLanguage) -> String {
        var output = line
            .replacingOccurrences(of: "·", with: " ")
            .replacingOccurrences(of: "•", with: " ")
            .replacingOccurrences(of: "▪", with: " ")
            .replacingOccurrences(of: "▫", with: " ")
            .replacingOccurrences(of: "○", with: " ")
            .replacingOccurrences(of: "●", with: " ")
            .replacingOccurrences(of: "♥", with: " ")
            .replacingOccurrences(of: "♡", with: " ")

        switch language {
        case .korean:
            output = output.replacingOccurrences(
                of: #"(?<=\s|^)[A-Za-z](?=\s|$)"#,
                with: "",
                options: .regularExpression
            )
            output = output.replacingOccurrences(
                of: #"[^0-9A-Za-z가-힣ᄀ-ᇿ㄰-㆏\u3400-\u4DBF\u4E00-\u9FFF\s\.\,\!\?\-\'\"\~]"#,
                with: " ",
                options: .regularExpression
            )
        case .chinese:
            output = output.replacingOccurrences(
                of: #"[^0-9A-Za-z\u3400-\u4DBF\u4E00-\u9FFF\s，。！？：；、“”‘’（）\(\)\.\,\!\?\-]"#,
                with: " ",
                options: .regularExpression
            )
        case .english:
            output = output.replacingOccurrences(
                of: #"[^0-9A-Za-z\s\.\,\!\?\-\'\"\:\;\(\)]"#,
                with: " ",
                options: .regularExpression
            )
        case .japanese:
            break
        }

        return output
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldKeepScalar(_ scalar: UnicodeScalar) -> Bool {
        if CharacterSet.controlCharacters.contains(scalar) {
            return false
        }
        if scalar.value == 0x200D || scalar.value == 0xFE0E || scalar.value == 0xFE0F {
            return false
        }
        if scalar.properties.isEmoji || scalar.properties.isEmojiPresentation {
            return false
        }
        if CharacterSet.symbols.contains(scalar) {
            return false
        }
        return true
    }

    private static func similarityScore(lhs: String, rhs: String) -> Double {
        if lhs == rhs {
            return 1.0
        }

        let left = Array(lhs)
        let right = Array(rhs)
        let maxLength = max(left.count, right.count)
        guard maxLength > 0 else {
            return 1.0
        }

        var previous = Array(0 ... right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftIndex + 1

            for (rightIndex, rightCharacter) in right.enumerated() {
                let substitutionCost = leftCharacter == rightCharacter ? 0 : 1
                current[rightIndex + 1] = min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    previous[rightIndex] + substitutionCost
                )
            }
            previous = current
        }

        let distance = previous[right.count]
        return 1.0 - (Double(distance) / Double(maxLength))
    }

    private static func shouldMergeRecognizedTexts(
        _ lhs: String,
        _ rhs: String,
        language: TranslationLanguage
    ) -> Bool {
        if lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs) {
            return true
        }

        let rawSimilarity = similarityScore(lhs: lhs, rhs: rhs)
        let rawThreshold: Double
        switch language {
        case .japanese:
            rawThreshold = 0.72
        case .chinese, .korean:
            rawThreshold = 0.75
        case .english:
            rawThreshold = 0.78
        }
        if rawSimilarity >= rawThreshold {
            return true
        }

        let leftKey = comparisonKey(for: lhs)
        let rightKey = comparisonKey(for: rhs)
        guard !leftKey.isEmpty, !rightKey.isEmpty else {
            return false
        }
        if leftKey == rightKey || leftKey.contains(rightKey) || rightKey.contains(leftKey) {
            return true
        }

        let normalizedThreshold: Double = language == .japanese ? 0.66 : 0.72
        return similarityScore(lhs: leftKey, rhs: rightKey) >= normalizedThreshold
    }

    private static func comparisonKey(for text: String) -> String {
        let filtered = text.unicodeScalars.filter { scalar in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return false
            }
            if CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar) {
                return false
            }
            return true
        }
        return String(String.UnicodeScalarView(filtered)).lowercased()
    }

    private static func mergeAdjacentDuplicateSubtitles(
        _ subtitles: [SubtitleItem],
        maxGap: Double,
        language: TranslationLanguage
    ) -> [SubtitleItem] {
        guard !subtitles.isEmpty else {
            return subtitles
        }

        var merged: [SubtitleItem] = [subtitles[0]]
        for subtitle in subtitles.dropFirst() {
            guard var previous = merged.last else {
                merged.append(subtitle)
                continue
            }

            let gap = max(0.0, subtitle.startTime - previous.endTime)
            if gap <= maxGap && shouldMergeRecognizedTexts(previous.text, subtitle.text, language: language) {
                previous.endTime = max(previous.endTime, subtitle.endTime)
                if subtitle.text.count >= previous.text.count {
                    previous.text = subtitle.text
                }
                merged[merged.count - 1] = previous
            } else {
                merged.append(subtitle)
            }
        }

        for index in merged.indices {
            merged[index].index = index + 1
        }
        return merged
    }
}

private struct OCRCandidate {
    let text: String
    let averageConfidence: Double
    let scriptCoverage: Double
    let score: Double
}
