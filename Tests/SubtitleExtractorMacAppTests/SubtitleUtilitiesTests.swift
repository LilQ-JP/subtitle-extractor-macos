@testable import SubtitleExtractorMacApp
import AppKit
import AVFoundation
import XCTest

final class SubtitleUtilitiesTests: XCTestCase {
    func testSRTParsing() throws {
        let contents = """
1
00:00:14,000 --> 00:00:45,000
こんにちは

2
00:00:20,000 --> 00:00:25,000
世界
"""

        let subtitles = SubtitleUtilities.parseSRT(contents: contents)

        XCTAssertEqual(subtitles.count, 2)
        XCTAssertEqual(subtitles[0].startTime, 14.0, accuracy: 0.001)
        XCTAssertEqual(subtitles[1].text, "世界")
    }

    func testTimingNormalizationRemovesOverlap() {
        let subtitles = [
            SubtitleItem(index: 1, startTime: 14.0, endTime: 45.0, text: "A"),
            SubtitleItem(index: 2, startTime: 20.0, endTime: 22.0, text: "B"),
        ]

        let normalized = SubtitleUtilities.normalizeSubtitles(
            subtitles,
            minDuration: 0.5,
            maxDuration: 10.0,
            timelineEnd: 60.0
        )

        XCTAssertEqual(normalized[0].endTime, 19.99, accuracy: 0.02)
        XCTAssertGreaterThan(normalized[1].endTime, normalized[1].startTime)
    }

    func testTimingNormalizationBridgesGapToNextSubtitle() {
        let subtitles = [
            SubtitleItem(index: 1, startTime: 4.0, endTime: 4.6, text: "A"),
            SubtitleItem(index: 2, startTime: 7.0, endTime: 7.8, text: "B"),
        ]

        let normalized = SubtitleUtilities.normalizeSubtitles(
            subtitles,
            minDuration: 0.5,
            maxDuration: 10.0,
            timelineEnd: 12.0
        )

        XCTAssertEqual(normalized[0].endTime, 6.99, accuracy: 0.02)
        XCTAssertEqual(normalized[1].endTime, 11.99, accuracy: 0.02)
    }

    func testSubtitleLookupMatchesPlaybackTime() {
        let subtitles = [
            SubtitleItem(index: 1, startTime: 1.0, endTime: 2.0, text: "A"),
            SubtitleItem(index: 2, startTime: 3.0, endTime: 4.0, text: "B"),
        ]

        XCTAssertEqual(SubtitleUtilities.subtitle(containing: 1.5, in: subtitles)?.index, 1)
        XCTAssertEqual(SubtitleUtilities.subtitle(containing: 4.0, in: subtitles)?.index, 2)
        XCTAssertNil(SubtitleUtilities.subtitle(containing: 2.4, in: subtitles))
    }

    func testWidthBasedWrapping() {
        let font = NSFont.systemFont(ofSize: 24, weight: .regular)
        let wrapped = SubtitleUtilities.wrapText(
            "これはとても長い字幕なので指定幅で自動改行される必要があります",
            maxWidth: 180,
            font: font
        )

        XCTAssertTrue(wrapped.contains("\n"))
        for line in wrapped.components(separatedBy: "\n") {
            XCTAssertLessThanOrEqual(
                SubtitleUtilities.measureTextWidth(line, font: font),
                180.5
            )
        }
    }

    func testDictionaryEntrySerialization() {
        let entry = DictionaryEntry(source: "主人公", target: "Hero")
        let incomplete = DictionaryEntry(source: "敵", target: "")

        XCTAssertEqual(entry.serialized, "主人公=Hero")
        XCTAssertNil(incomplete.serialized)
    }

    func testExtractionProgressFraction() {
        let progress = ExtractionProgress(processed: 15, total: 60, timestamp: 12.5)

        XCTAssertEqual(progress.fractionCompleted, 0.25, accuracy: 0.0001)
    }

    func testFitSubtitleLayoutKeepsTextInsideRegion() {
        let layout = SubtitleUtilities.fitSubtitleLayout(
            text: "これは非常に長い翻訳字幕で、字幕枠の中に必ず収まるように自動改行と必要に応じた縮小が行われる必要があります。",
            regionSize: CGSize(width: 220, height: 60),
            fontName: "Hiragino Sans",
            preferredFontSize: 28,
            outlineWidth: 4
        )

        let measured = SubtitleUtilities.measureSubtitleText(
            layout.text,
            fontName: "Hiragino Sans",
            fontSize: CGFloat(layout.fontSize),
            outlineWidth: CGFloat(layout.outlineWidth),
            maxSize: CGSize(width: 220, height: CGFloat.greatestFiniteMagnitude)
        )

        XCTAssertFalse(layout.text.isEmpty)
        XCTAssertLessThanOrEqual(layout.fontSize, 28.0)
        XCTAssertLessThanOrEqual(measured.height, 60.5)
    }

    func testFontSearchMatchesNormalizedQuery() {
        XCTAssertTrue(SubtitleUtilities.fontMatches(name: "Hiragino Sans W6", query: "hiragino"))
        XCTAssertTrue(SubtitleUtilities.fontMatches(name: "A-OTF Shin Go Pro", query: "shingo"))
        XCTAssertTrue(SubtitleUtilities.fontMatches(name: "游ゴシック", query: "游 ゴシ"))
        XCTAssertTrue(SubtitleUtilities.searchMatches(text: "字幕 修正 テスト", query: "修正"))
    }

    func testDetectChromaKeyColorPrefersGreenCenter() {
        let image = makeOverlayImage()

        let detected = SubtitleUtilities.detectChromaKeyColor(in: image)

        XCTAssertNotNil(detected)
        XCTAssertGreaterThan(detected?.green ?? 0.0, 0.65)
        XCTAssertLessThan(detected?.red ?? 1.0, 0.25)
        XCTAssertLessThan(detected?.blue ?? 1.0, 0.25)
    }

    func testProcessOverlayImageReturnsTransparentRect() {
        let image = makeOverlayImage()

        let result = SubtitleUtilities.processOverlayImage(
            image,
            keyColor: RGBColor(red: 0.0, green: 1.0, blue: 0.0),
            tolerance: 0.20,
            softness: 0.05
        )

        XCTAssertNotNil(result.processedTIFFData)
        XCTAssertNotNil(result.transparentRect)
        XCTAssertEqual(result.transparentRect?.x ?? 0.0, 0.10, accuracy: 0.06)
        XCTAssertEqual(result.transparentRect?.width ?? 0.0, 0.55, accuracy: 0.06)
        XCTAssertEqual(result.transparentRect?.height ?? 0.0, 0.50, accuracy: 0.06)
    }

    @MainActor
    func testSubtitleImageContainsVisiblePixels() {
        let image = SubtitleUtilities.subtitleImage(
            text: "こんにちは世界 これは書き出しテストです",
            size: CGSize(width: 288, height: 40),
            fontName: "Hiragino Sans",
            fontSize: 24,
            outlineWidth: 4
        )

        XCTAssertNotNil(image)
        let visiblePixels = countVisiblePixels(
            in: image!,
            region: CGRect(x: 0, y: 0, width: 288, height: 40)
        )
        let brightPixels = countBrightPixels(
            in: image!,
            region: CGRect(x: 0, y: 0, width: 288, height: 40)
        )
        XCTAssertGreaterThan(visiblePixels, 80)
        XCTAssertGreaterThan(brightPixels, 80)
    }

    @MainActor
    func testAdditionalSubtitleBannerImageContainsVisiblePixels() {
        let image = SubtitleUtilities.additionalSubtitleBannerImage(
            text: "ん？",
            size: CGSize(width: 300, height: 54),
            fontName: "Hiragino Sans",
            fontSize: 24,
            backgroundOpacity: 0.78
        )

        XCTAssertNotNil(image)
        let visiblePixels = countVisiblePixels(
            in: image!,
            region: CGRect(x: 0, y: 0, width: 300, height: 54)
        )
        let centerColor = pixelColor(in: image!, at: CGPoint(x: 150, y: 27))
        XCTAssertGreaterThan(visiblePixels, 2_000)
        XCTAssertGreaterThan(centerColor.red, 0.65)
        XCTAssertGreaterThan(centerColor.green, 0.70)
        XCTAssertGreaterThan(centerColor.blue, 0.74)
    }

    @MainActor
    func testVideoBurnInExporterCreatesMP4AndMOV() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("input.mov")
        try makeSampleVideo(url: inputURL, size: CGSize(width: 320, height: 180), fps: 30, frameCount: 24)

        let subtitles = [
            SubtitleItem(
                index: 1,
                startTime: 0.10,
                endTime: 0.65,
                text: "こんにちは世界 これは書き出しテストです"
            ),
        ]

        for format in [ExportFormat.mp4, .mov] {
            let outputURL = tempDirectory.appendingPathComponent("output.\(format.suggestedFilenameExtension)")
            let request = VideoRenderRequest(
                sourceURL: inputURL,
                destinationURL: outputURL,
                format: format,
                subtitles: subtitles,
                textMode: .original,
                subtitleRect: NormalizedRect(x: 0.08, y: 0.72, width: 0.84, height: 0.18),
                fontName: "Hiragino Sans",
                fontSize: 24,
                outlineWidth: 4,
                overlayImage: nil,
                outputSize: CGSize(width: 320, height: 180),
                videoRect: nil
            )

            let baselineURL = tempDirectory.appendingPathComponent("baseline.\(format.suggestedFilenameExtension)")
            let baselineRequest = VideoRenderRequest(
                sourceURL: inputURL,
                destinationURL: baselineURL,
                format: format,
                subtitles: [],
                textMode: .original,
                subtitleRect: request.subtitleRect,
                fontName: request.fontName,
                fontSize: request.fontSize,
                outlineWidth: request.outlineWidth,
                overlayImage: nil,
                outputSize: request.outputSize,
                videoRect: nil
            )

            try await VideoBurnInExporter.export(baselineRequest)
            try await VideoBurnInExporter.export(request)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
            let fileSize = (try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.intValue ?? 0
            XCTAssertGreaterThan(fileSize, 1_000)

            let frame = try frameImage(url: outputURL, at: 0.30)
            let baselineFrame = try frameImage(url: baselineURL, at: 0.30)
            let changedPixels = countChangedPixels(
                reference: baselineFrame,
                compared: frame,
                region: CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
            )
            XCTAssertGreaterThan(changedPixels, 120)
        }

        let overlaySource = makeOverlayImage()
        let overlayResult = SubtitleUtilities.processOverlayImage(
            overlaySource,
            keyColor: RGBColor(red: 0.0, green: 1.0, blue: 0.0),
            tolerance: 0.20,
            softness: 0.05
        )
        let overlayImage = overlayResult.processedTIFFData.flatMap(NSImage.init(data:))
        XCTAssertNotNil(overlayImage)

        let overlayOutputURL = tempDirectory.appendingPathComponent("overlay_output.mp4")
        let overlayRequest = VideoRenderRequest(
            sourceURL: inputURL,
            destinationURL: overlayOutputURL,
            format: .mp4,
            subtitles: subtitles,
            textMode: .original,
            subtitleRect: NormalizedRect(x: 0.08, y: 0.80, width: 0.84, height: 0.12),
            fontName: "Hiragino Sans",
            fontSize: 24,
            outlineWidth: 4,
            overlayImage: overlayImage,
            outputSize: overlayImage?.size,
            videoRect: overlayResult.transparentRect,
            videoOffset: .zero,
            videoZoom: 1.0
        )

        let overlayBaselineURL = tempDirectory.appendingPathComponent("overlay_baseline.mp4")
        let overlayBaselineRequest = VideoRenderRequest(
            sourceURL: inputURL,
            destinationURL: overlayBaselineURL,
            format: .mp4,
            subtitles: [],
            textMode: .original,
            subtitleRect: overlayRequest.subtitleRect,
            fontName: overlayRequest.fontName,
            fontSize: overlayRequest.fontSize,
            outlineWidth: overlayRequest.outlineWidth,
            overlayImage: overlayRequest.overlayImage,
            outputSize: overlayRequest.outputSize,
            videoRect: overlayRequest.videoRect,
            videoOffset: overlayRequest.videoOffset,
            videoZoom: overlayRequest.videoZoom
        )

        try await VideoBurnInExporter.export(overlayBaselineRequest)
        try await VideoBurnInExporter.export(overlayRequest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: overlayOutputURL.path))

        let overlayFrame = try frameImage(url: overlayOutputURL, at: 0.30)
        let overlayBaselineFrame = try frameImage(url: overlayBaselineURL, at: 0.30)
        let overlayChangedPixels = countChangedPixels(
            reference: overlayBaselineFrame,
            compared: overlayFrame,
            region: CGRect(x: 0, y: 0, width: overlayFrame.width, height: overlayFrame.height)
        )
        XCTAssertGreaterThan(overlayChangedPixels, 80)
        let sampled = pixelColor(
            in: overlayFrame,
            at: CGPoint(x: 110, y: 105)
        )
        XCTAssertGreaterThan(sampled.red, 0.08)
        XCTAssertGreaterThan(sampled.blue, 0.10)
        XCTAssertLessThan(sampled.green, 0.85)
    }

    @MainActor
    func testTranslatedSubtitleExportWrapsInsideRequestedRegion() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("input.mov")
        try makeSampleVideo(url: inputURL, size: CGSize(width: 320, height: 180), fps: 30, frameCount: 24)

        let subtitleRect = NormalizedRect(x: 0.10, y: 0.62, width: 0.46, height: 0.24)
        let subtitles = [
            SubtitleItem(
                index: 1,
                startTime: 0.10,
                endTime: 0.65,
                text: "short",
                translated: "This translated subtitle is intentionally long so it must wrap into multiple lines and still stay inside the requested caption area."
            ),
        ]

        let baselineURL = tempDirectory.appendingPathComponent("baseline.mp4")
        let baselineRequest = VideoRenderRequest(
            sourceURL: inputURL,
            destinationURL: baselineURL,
            format: .mp4,
            subtitles: [],
            textMode: .translated,
            subtitleRect: subtitleRect,
            fontName: "Hiragino Sans",
            fontSize: 24,
            outlineWidth: 4,
            overlayImage: nil,
            outputSize: CGSize(width: 320, height: 180),
            videoRect: nil
        )
        try await VideoBurnInExporter.export(baselineRequest)

        let outputURL = tempDirectory.appendingPathComponent("translated.mp4")
        let request = VideoRenderRequest(
            sourceURL: inputURL,
            destinationURL: outputURL,
            format: .mp4,
            subtitles: subtitles,
            textMode: .translated,
            subtitleRect: subtitleRect,
            fontName: "Hiragino Sans",
            fontSize: 24,
            outlineWidth: 4,
            overlayImage: nil,
            outputSize: CGSize(width: 320, height: 180),
            videoRect: nil
        )

        try await VideoBurnInExporter.export(request)

        let baselineFrame = try frameImage(url: baselineURL, at: 0.30)
        let frame = try frameImage(url: outputURL, at: 0.30)
        let changedBounds = changedPixelBounds(reference: baselineFrame, compared: frame)

        XCTAssertNotNil(changedBounds)
        guard let changedBounds else {
            return
        }

        let expectedRect = pixelRect(for: subtitleRect, in: CGSize(width: frame.width, height: frame.height))
        XCTAssertGreaterThan(changedBounds.height, 24)
        XCTAssertGreaterThan(expectedRect.maxX + 2, changedBounds.maxX)
        XCTAssertLessThan(expectedRect.minX - 2, changedBounds.minX)
    }

    @MainActor
    func testVideoBurnInExporterRendersAdditionalSubtitleBanner() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("input.mov")
        try makeSampleVideo(url: inputURL, size: CGSize(width: 320, height: 180), fps: 30, frameCount: 24)

        let baselineURL = tempDirectory.appendingPathComponent("baseline.mp4")
        let baselineRequest = VideoRenderRequest(
            sourceURL: inputURL,
            destinationURL: baselineURL,
            format: .mp4,
            subtitles: [],
            textMode: .original,
            subtitleRect: NormalizedRect(x: 0.08, y: 0.72, width: 0.84, height: 0.18),
            fontName: "Hiragino Sans",
            fontSize: 24,
            outlineWidth: 4,
            overlayImage: nil,
            outputSize: CGSize(width: 320, height: 180),
            videoRect: nil
        )

        let outputURL = tempDirectory.appendingPathComponent("additional_banner.mp4")
        let request = VideoRenderRequest(
            sourceURL: inputURL,
            destinationURL: outputURL,
            format: .mp4,
            subtitles: [
                SubtitleItem(
                    index: 1,
                    startTime: 0.10,
                    endTime: 0.65,
                    text: "",
                    additionalText: "ん？"
                ),
            ],
            textMode: .original,
            subtitleRect: baselineRequest.subtitleRect,
            fontName: "Hiragino Sans",
            fontSize: 24,
            outlineWidth: 4,
            additionalSubtitleRect: .defaultAdditionalBannerArea,
            additionalSubtitleFontSize: 24,
            additionalSubtitleBackgroundOpacity: 0.78,
            overlayImage: nil,
            outputSize: CGSize(width: 320, height: 180),
            videoRect: nil
        )

        try await VideoBurnInExporter.export(baselineRequest)
        try await VideoBurnInExporter.export(request)

        let baselineFrame = try frameImage(url: baselineURL, at: 0.30)
        let frame = try frameImage(url: outputURL, at: 0.30)
        let bannerRect = bitmapRect(for: .defaultAdditionalBannerArea, in: CGSize(width: frame.width, height: frame.height))
        let changedPixels = countChangedPixels(reference: baselineFrame, compared: frame, region: bannerRect)

        XCTAssertGreaterThan(changedPixels, 2_500)
        let sample = pixelColor(in: frame, at: CGPoint(x: bannerRect.midX, y: bannerRect.midY))
        XCTAssertGreaterThan(sample.red, 0.62)
        XCTAssertGreaterThan(sample.green, 0.68)
        XCTAssertGreaterThan(sample.blue, 0.72)
    }

    @MainActor
    func testOverlayVideoExportFitsInsideWindowWithoutCroppingAtDefaultZoom() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("input.mov")
        try makeSampleVideo(url: inputURL, size: CGSize(width: 320, height: 180), fps: 30, frameCount: 24)

        let outputURL = tempDirectory.appendingPathComponent("fit_window.mp4")
        let request = VideoRenderRequest(
            sourceURL: inputURL,
            destinationURL: outputURL,
            format: .mp4,
            subtitles: [],
            textMode: .original,
            subtitleRect: NormalizedRect(x: 0.10, y: 0.72, width: 0.84, height: 0.16),
            fontName: "Hiragino Sans",
            fontSize: 24,
            outlineWidth: 4,
            overlayImage: nil,
            outputSize: CGSize(width: 320, height: 320),
            videoRect: NormalizedRect(x: 0.18, y: 0.18, width: 0.44, height: 0.44),
            videoOffset: .zero,
            videoZoom: 1.0
        )

        try await VideoBurnInExporter.export(request)

        let frame = try frameImage(url: outputURL, at: 0.30)
        let videoWindow = pixelRect(for: request.videoRect!, in: CGSize(width: frame.width, height: frame.height))
        let visibleBounds = visiblePixelBounds(in: frame, within: videoWindow)
        let topInsideWindow = pixelColor(in: frame, at: CGPoint(x: videoWindow.midX, y: videoWindow.maxY - 4))

        XCTAssertNotNil(visibleBounds)
        XCTAssertLessThan(topInsideWindow.red + topInsideWindow.green + topInsideWindow.blue, 0.25)
        XCTAssertGreaterThan(visibleBounds?.width ?? 0.0, videoWindow.width - 12.0)
        XCTAssertLessThan(visibleBounds?.height ?? .greatestFiniteMagnitude, videoWindow.height - 24.0)
    }

    private func makeOverlayImage() -> NSImage {
        let size = NSSize(width: 400, height: 240)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        NSColor(calibratedRed: 0.02, green: 0.97, blue: 0.04, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(x: 40, y: 72, width: 220, height: 120)).fill()

        image.unlockFocus()
        return image
    }

    private func makeSampleVideo(url: URL, size: CGSize, fps: Int32, frameCount: Int) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ]
        )

        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)

        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0 ..< frameCount {
            while !input.isReadyForMoreMediaData {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }

            guard let pixelBuffer = makePixelBuffer(
                size: size,
                color: frameIndex.isMultiple(of: 2)
                    ? NSColor(calibratedRed: 0.10, green: 0.32, blue: 0.82, alpha: 1.0)
                    : NSColor(calibratedRed: 0.18, green: 0.62, blue: 0.28, alpha: 1.0)
            ) else {
                XCTFail("Failed to create pixel buffer")
                return
            }

            let time = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: time))
        }

        input.markAsFinished()
        let finishExpectation = expectation(description: "finishWriting")
        writer.finishWriting {
            finishExpectation.fulfill()
        }
        wait(for: [finishExpectation], timeout: 10.0)
        XCTAssertEqual(writer.status, .completed)
    }

    private func makePixelBuffer(size: CGSize, color: NSColor) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]

        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard result == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let context = CGContext(
            data: baseAddress,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }

        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        return pixelBuffer
    }

    private func frameImage(url: URL, at seconds: Double) throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
    }

    private func countBrightPixels(in image: CGImage, region: CGRect) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let imageRegion = clampedRegion(region, width: image.width, height: image.height) else {
            return 0
        }
        var count = 0

        for y in Int(imageRegion.minY) ..< Int(imageRegion.maxY) {
            for x in Int(imageRegion.minX) ..< Int(imageRegion.maxX) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                let red = Double(color.redComponent)
                let green = Double(color.greenComponent)
                let blue = Double(color.blueComponent)
                let luminance = red * 0.299 + green * 0.587 + blue * 0.114
                if luminance > 0.72 {
                    count += 1
                }
            }
        }

        return count
    }

    private func countVisiblePixels(in image: CGImage, region: CGRect) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let imageRegion = clampedRegion(region, width: image.width, height: image.height) else {
            return 0
        }
        var count = 0

        for y in Int(imageRegion.minY) ..< Int(imageRegion.maxY) {
            for x in Int(imageRegion.minX) ..< Int(imageRegion.maxX) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                if Double(color.alphaComponent) > 0.05 {
                    count += 1
                }
            }
        }

        return count
    }

    private func pixelColor(in image: CGImage, at point: CGPoint) -> (red: Double, green: Double, blue: Double) {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard image.width > 0,
              image.height > 0 else {
            return (0, 0, 0)
        }
        let clampedX = min(max(Int(point.x.rounded()), 0), image.width - 1)
        let clampedY = min(max(Int(point.y.rounded()), 0), image.height - 1)
        guard let color = bitmap.colorAt(x: clampedX, y: clampedY)?.usingColorSpace(.deviceRGB) else {
            return (0, 0, 0)
        }

        return (
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent)
        )
    }

    private func countChangedPixels(reference: CGImage, compared: CGImage, region: CGRect) -> Int {
        guard reference.width == compared.width,
              reference.height == compared.height,
              let imageRegion = clampedRegion(region, width: reference.width, height: reference.height) else {
            return 0
        }
        let referenceBitmap = NSBitmapImageRep(cgImage: reference)
        let comparedBitmap = NSBitmapImageRep(cgImage: compared)
        var count = 0

        for y in Int(imageRegion.minY) ..< Int(imageRegion.maxY) {
            for x in Int(imageRegion.minX) ..< Int(imageRegion.maxX) {
                guard let referenceColor = referenceBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let comparedColor = comparedBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                let redDelta = abs(Double(referenceColor.redComponent - comparedColor.redComponent))
                let greenDelta = abs(Double(referenceColor.greenComponent - comparedColor.greenComponent))
                let blueDelta = abs(Double(referenceColor.blueComponent - comparedColor.blueComponent))
                let alphaDelta = abs(Double(referenceColor.alphaComponent - comparedColor.alphaComponent))

                if max(redDelta, greenDelta, blueDelta, alphaDelta) > 0.015 {
                    count += 1
                }
            }
        }

        return count
    }

    private func changedPixelBounds(reference: CGImage, compared: CGImage) -> CGRect? {
        guard reference.width == compared.width,
              reference.height == compared.height else {
            return nil
        }

        let referenceBitmap = NSBitmapImageRep(cgImage: reference)
        let comparedBitmap = NSBitmapImageRep(cgImage: compared)
        var minX = reference.width
        var minY = reference.height
        var maxX = -1
        var maxY = -1

        for y in 0 ..< reference.height {
            for x in 0 ..< reference.width {
                guard let referenceColor = referenceBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let comparedColor = comparedBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                let redDelta = abs(Double(referenceColor.redComponent - comparedColor.redComponent))
                let greenDelta = abs(Double(referenceColor.greenComponent - comparedColor.greenComponent))
                let blueDelta = abs(Double(referenceColor.blueComponent - comparedColor.blueComponent))
                let alphaDelta = abs(Double(referenceColor.alphaComponent - comparedColor.alphaComponent))

                if max(redDelta, greenDelta, blueDelta, alphaDelta) > 0.015 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return nil
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    private func visiblePixelBounds(in image: CGImage, within region: CGRect) -> CGRect? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let imageRegion = clampedRegion(region, width: image.width, height: image.height) else {
            return nil
        }

        var minX = image.width
        var minY = image.height
        var maxX = -1
        var maxY = -1

        for y in Int(imageRegion.minY) ..< Int(imageRegion.maxY) {
            for x in Int(imageRegion.minX) ..< Int(imageRegion.maxX) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                let luminance = Double(color.redComponent) * 0.299 +
                    Double(color.greenComponent) * 0.587 +
                    Double(color.blueComponent) * 0.114

                if luminance > 0.15 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return nil
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    private func pixelRect(for normalizedRect: NormalizedRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalizedRect.x * size.width,
            y: size.height - (normalizedRect.y + normalizedRect.height) * size.height,
            width: normalizedRect.width * size.width,
            height: normalizedRect.height * size.height
        ).integral
    }

    private func bitmapRect(for normalizedRect: NormalizedRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalizedRect.x * size.width,
            y: normalizedRect.y * size.height,
            width: normalizedRect.width * size.width,
            height: normalizedRect.height * size.height
        ).integral
    }

    private func clampedRegion(_ region: CGRect, width: Int, height: Int) -> CGRect? {
        let clamped = region.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard clamped.width > 0, clamped.height > 0 else {
            return nil
        }
        return clamped
    }

    private func makeBitmapContext(width: Int, height: Int) -> CGContext? {
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
}
