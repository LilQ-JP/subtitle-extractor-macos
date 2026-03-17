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

    func testTimingNormalizationPreservesExistingGap() {
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

        XCTAssertEqual(normalized[0].endTime, 4.6, accuracy: 0.02)
        XCTAssertEqual(normalized[1].endTime, 7.8, accuracy: 0.02)
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

    func testWrapTimingChangesLineCount() {
        let font = NSFont.systemFont(ofSize: 24, weight: .regular)
        let source = "これはとても長い字幕なので指定幅の中で改行タイミングを変えた時に行数が変わる必要があります"

        let early = SubtitleUtilities.wrapText(
            source,
            maxWidth: 220,
            font: font,
            timingMode: .early
        )
        let late = SubtitleUtilities.wrapText(
            source,
            maxWidth: 220,
            font: font,
            timingMode: .late
        )

        XCTAssertGreaterThanOrEqual(
            SubtitleUtilities.lineCount(of: early),
            SubtitleUtilities.lineCount(of: late)
        )
    }

    func testPreferredLineCountIsAppliedDuringFitting() {
        let layout = SubtitleUtilities.fitSubtitleLayout(
            text: "This translated subtitle is long enough that it should rebalance into fewer preferred lines while still staying inside the region.",
            regionSize: CGSize(width: 320, height: 90),
            fontName: "Hiragino Sans",
            preferredFontSize: 28,
            outlineWidth: 4,
            timingMode: .balanced,
            preferredLineCount: 2
        )

        XCTAssertLessThanOrEqual(SubtitleUtilities.lineCount(of: layout.text), 2)
    }

    func testPortraitDefaultsUseWiderCaptionArea() {
        let portraitRegion = SubtitleUtilities.defaultSubtitleRegion(for: CGSize(width: 1080, height: 1920))
        let portraitLayout = SubtitleUtilities.defaultSubtitleLayoutRect(for: CGSize(width: 1080, height: 1920), wrapWidthRatio: 0.68)
        let landscapeLayout = SubtitleUtilities.defaultSubtitleLayoutRect(for: CGSize(width: 1920, height: 1080), wrapWidthRatio: 0.68)

        XCTAssertGreaterThan(portraitRegion.height, NormalizedRect.defaultSubtitleArea.height)
        XCTAssertGreaterThan(portraitLayout.width, landscapeLayout.width)
    }

    @MainActor
    func testVideoLoaderLoadsPortraitVideo() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("portrait_loader.mov")
        try makeSampleVideo(url: inputURL, size: CGSize(width: 360, height: 640), fps: 30, frameCount: 18)

        let loaded = try await VideoLoader.load(url: inputURL)
        XCTAssertEqual(loaded.metadata.width, 360)
        XCTAssertEqual(loaded.metadata.height, 640)
    }

    func testDictionaryEntrySerialization() {
        let entry = DictionaryEntry(source: "主人公", target: "Hero")
        let incomplete = DictionaryEntry(source: "敵", target: "")

        XCTAssertEqual(entry.serialized, "主人公=Hero")
        XCTAssertNil(incomplete.serialized)
    }

    func testDictionaryEntryRespectsLanguageScopesAndVideoToggle() {
        let entry = DictionaryEntry(
            source: "先生",
            target: "Sensei",
            sourceLanguageScope: .japanese,
            targetLanguageScope: .english,
            isEnabledForCurrentVideo: false
        )

        XCTAssertFalse(
            entry.matches(
                sourceLanguage: .japanese,
                targetLanguage: .english,
                useForCurrentVideo: true
            )
        )
        XCTAssertTrue(
            entry.matches(
                sourceLanguage: .japanese,
                targetLanguage: .english,
                useForCurrentVideo: false
            )
        )
        XCTAssertFalse(
            entry.matches(
                sourceLanguage: .korean,
                targetLanguage: .english,
                useForCurrentVideo: false
            )
        )
        XCTAssertEqual(
            entry.serialized(
                forSourceLanguage: .japanese,
                targetLanguage: .english,
                useForCurrentVideo: false
            ),
            "先生=Sensei"
        )
        XCTAssertNil(
            entry.serialized(
                forSourceLanguage: .japanese,
                targetLanguage: .korean,
                useForCurrentVideo: false
            )
        )
    }

    func testExtractionProgressFraction() {
        let progress = ExtractionProgress(processed: 15, total: 60, timestamp: 12.5)

        XCTAssertEqual(progress.fractionCompleted, 0.25, accuracy: 0.0001)
    }

    func testTranslationProgressFraction() {
        let progress = TranslationProgress(processed: 3, total: 8, currentText: "こんにちは")

        XCTAssertEqual(progress.fractionCompleted, 0.375, accuracy: 0.0001)
        XCTAssertEqual(progress.currentText, "こんにちは")
    }

    func testTranslationProgressPayloadDecodesCurrentText() throws {
        let json = #"{"event":"translate_progress","processed":2,"total":5,"current_text":"ありがとう"}"#
        let payload = try JSONDecoder().decode(BackendTranslationProgressPayload.self, from: Data(json.utf8))

        XCTAssertEqual(payload.event, "translate_progress")
        XCTAssertEqual(payload.processed, 2)
        XCTAssertEqual(payload.total, 5)
        XCTAssertEqual(payload.currentText, "ありがとう")
    }

    func testUpdateInstallerDownloadAndStorePreservesDownloadedFile() async throws {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = workingDirectory.appendingPathComponent("CaptionStudio-9.9.9-macOS.pkg")
        let updatesDirectory = workingDirectory.appendingPathComponent("Updates", isDirectory: true)
        let expectedData = Data("caption-studio-update".utf8)

        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try expectedData.write(to: sourceURL, options: .atomic)

        let previousOverride = getenv("CAPTIONSTUDIO_UPDATES_DIR_OVERRIDE").map { String(cString: $0) }
        setenv("CAPTIONSTUDIO_UPDATES_DIR_OVERRIDE", updatesDirectory.path, 1)
        defer {
            if let previousOverride {
                setenv("CAPTIONSTUDIO_UPDATES_DIR_OVERRIDE", previousOverride, 1)
            } else {
                unsetenv("CAPTIONSTUDIO_UPDATES_DIR_OVERRIDE")
            }
            try? FileManager.default.removeItem(at: workingDirectory)
        }

        let asset = AppUpdateAsset(
            name: "CaptionStudio-9.9.9-macOS.pkg",
            downloadURL: sourceURL,
            contentType: "application/octet-stream",
            size: Int64(expectedData.count),
            digest: nil
        )
        let update = AppUpdateInfo(
            title: "Caption Studio 9.9.9",
            version: "9.9.9",
            releaseNotes: "",
            publishedAt: nil,
            releasePageURL: ProductConstants.releasesPageURL,
            assets: [asset]
        )

        let storedURL = try await UpdateInstaller.downloadAndStore(update: update)

        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertEqual(try Data(contentsOf: storedURL), expectedData)
        XCTAssertEqual(UpdateInstaller.storedUpdateURL(for: update), storedURL)
    }

    func testProjectDocumentRoundTrip() throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ProductConstants.projectFileExtension)
        let state = PersistentAppState()
        let document = SubtitleProjectDocument(
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            videoPath: "/tmp/example.mov",
            subtitles: [
                SubtitleItem(index: 1, startTime: 1.0, endTime: 2.0, text: "こんにちは", translated: "Hello"),
            ],
            selectedSubtitleID: nil,
            selectedSubtitleIDs: nil,
            persistentState: state
        )

        try ProjectStore.save(document, to: temporaryURL)
        let loaded = try ProjectStore.load(from: temporaryURL)

        XCTAssertEqual(loaded.videoPath, document.videoPath)
        XCTAssertEqual(loaded.subtitles.first?.translated, "Hello")
        XCTAssertEqual(loaded.schemaVersion, 1)
    }

    func testProjectStoreNormalizesProjectExtension() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let normalizedURL = ProjectStore.normalizedProjectURL(for: baseURL)

        XCTAssertEqual(normalizedURL.pathExtension, ProductConstants.projectFileExtension)
    }

    func testSubtitleProjectTypeHasExpectedExtension() {
        XCTAssertEqual(UTType.subtitleProject.preferredFilenameExtension, ProductConstants.projectFileExtension)
        XCTAssertTrue(UTType.subtitleProject.conforms(to: .json))
    }

    func testProjectStoreRecognizesLegacyJSONProjectFile() throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let payload = """
        {
          "savedAt": "2026-03-10T10:00:00Z",
          "videoPath": "/tmp/example.mov",
          "subtitles": [
            {
              "index": 1,
              "start_time": 0.0,
              "end_time": 1.0,
              "text": "Hello"
            }
          ],
          "persistentState": {}
        }
        """
        try XCTUnwrap(payload.data(using: .utf8)).write(to: temporaryURL)

        XCTAssertTrue(ProjectStore.looksLikeProjectFile(at: temporaryURL))
        let project = try ProjectStore.load(from: temporaryURL)
        XCTAssertEqual(project.subtitles.first?.text, "Hello")
    }

    func testProjectDocumentLoadFallsBackWhenSavedAtMissing() throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ProductConstants.projectFileExtension)
        let payload = """
        {
          "videoPath": "/tmp/example.mov",
          "subtitles": [
            {
              "index": 1,
              "start_time": 0.0,
              "end_time": 1.0,
              "text": "안녕하세요"
            }
          ]
        }
        """
        try XCTUnwrap(payload.data(using: .utf8)).write(to: temporaryURL)

        let project = try ProjectStore.load(from: temporaryURL)
        XCTAssertEqual(project.videoPath, "/tmp/example.mov")
        XCTAssertEqual(project.subtitles.first?.text, "안녕하세요")
    }

    func testProjectDocumentIgnoresInvalidPersistentState() throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ProductConstants.projectFileExtension)
        let payload = """
        {
          "savedAt": "2026-03-10T10:00:00Z",
          "videoPath": "/tmp/example.mov",
          "subtitles": [
            {
              "index": 1,
              "start_time": 0.0,
              "end_time": 1.0,
              "text": "你好"
            }
          ],
          "persistentState": {
            "appLanguage": "xx",
            "workspaceLayoutPreset": "broken"
          }
        }
        """
        try XCTUnwrap(payload.data(using: .utf8)).write(to: temporaryURL)

        let project = try ProjectStore.load(from: temporaryURL)
        XCTAssertEqual(project.subtitles.first?.text, "你好")
        XCTAssertEqual(project.persistentState.appLanguage, .japanese)
        XCTAssertEqual(project.persistentState.workspaceLayoutPreset, .balanced)
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
        XCTAssertGreaterThan(visiblePixels, 10)
        XCTAssertGreaterThan(brightPixels, 10)
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
            var progressSnapshots: [Double] = []
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
            try await VideoBurnInExporter.export(request) { fractionCompleted, _, _ in
                progressSnapshots.append(fractionCompleted)
            }

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
            let fileSize = (try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.intValue ?? 0
            XCTAssertGreaterThan(fileSize, 1_000)
            XCTAssertFalse(progressSnapshots.isEmpty)
            XCTAssertGreaterThanOrEqual(progressSnapshots.last ?? 0.0, 1.0)

            let frame = try frameImage(url: outputURL, at: 0.30)
            let baselineFrame = try frameImage(url: baselineURL, at: 0.30)
            let changedPixels = countChangedPixels(
                reference: baselineFrame,
                compared: frame,
                region: CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
            )
            XCTAssertGreaterThan(changedPixels, 120)
        }

        let portraitInputURL = tempDirectory.appendingPathComponent("portrait_input.mov")
        let portraitOutputURL = tempDirectory.appendingPathComponent("portrait.mp4")
        try makeSampleVideo(url: portraitInputURL, size: CGSize(width: 180, height: 320), fps: 30, frameCount: 24)
        let portraitRequest = VideoRenderRequest(
            sourceURL: portraitInputURL,
            destinationURL: portraitOutputURL,
            format: .mp4,
            subtitles: subtitles,
            textMode: .original,
            subtitleRect: SubtitleUtilities.defaultSubtitleLayoutRect(for: CGSize(width: 180, height: 320), wrapWidthRatio: 0.68),
            fontName: "Hiragino Sans",
            fontSize: 24,
            outlineWidth: 4,
            overlayImage: nil,
            outputSize: CGSize(width: 180, height: 320),
            videoRect: nil
        )

        try await VideoBurnInExporter.export(portraitRequest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: portraitOutputURL.path))
        let portraitFrame = try frameImage(url: portraitOutputURL, at: 0.30)
        XCTAssertEqual(portraitFrame.width, 180)
        XCTAssertEqual(portraitFrame.height, 320)

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
        XCTAssertGreaterThan(changedBounds.height, 20)
        XCTAssertGreaterThan(expectedRect.maxX + 2, changedBounds.maxX)
        XCTAssertLessThan(expectedRect.minX - 2, changedBounds.minX)
    }

    @MainActor
    func testVideoBurnInExporterRendersYouTubeCaptionStyle() async throws {
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
                    text: "字幕テスト"
                ),
            ],
            textMode: .original,
            subtitleRect: baselineRequest.subtitleRect,
            fontName: "Hiragino Sans",
            fontSize: 24,
            outlineWidth: 4,
            captionStyle: .youtube,
            overlayImage: nil,
            outputSize: CGSize(width: 320, height: 180),
            videoRect: nil
        )

        try await VideoBurnInExporter.export(baselineRequest)
        try await VideoBurnInExporter.export(request)

        let baselineFrame = try frameImage(url: baselineURL, at: 0.30)
        let frame = try frameImage(url: outputURL, at: 0.30)
        let captionRect = bitmapRect(for: baselineRequest.subtitleRect, in: CGSize(width: frame.width, height: frame.height))
        let changedPixels = countChangedPixels(reference: baselineFrame, compared: frame, region: captionRect)

        XCTAssertGreaterThan(changedPixels, 2_500)
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

    func testNativeOCRMergeFrameTextsMergesSimilarFrames() {
        let subtitles = NativeOCRExtractor.mergeFrameTexts([
            (time: 0.0, text: "Hello"),
            (time: 0.5, text: "Hello"),
            (time: 1.0, text: "Hello!"),
            (time: 2.0, text: "Next line"),
        ])

        XCTAssertEqual(subtitles.count, 2)
        XCTAssertEqual(subtitles[0].text, "Hello!")
        XCTAssertEqual(subtitles[0].startTime, 0.0, accuracy: 0.001)
        XCTAssertEqual(subtitles[0].endTime, 1.0, accuracy: 0.001)
        XCTAssertEqual(subtitles[1].text, "Next line")
    }

    func testNativeOCRMergeFrameTextsSplitsSameTextAcrossLargeGap() {
        let subtitles = NativeOCRExtractor.mergeFrameTexts(
            [
                (time: 0.0, text: "こんにちは"),
                (time: 0.5, text: "こんにちは"),
                (time: 2.0, text: "こんにちは"),
                (time: 2.5, text: "こんにちは"),
            ],
            sampleInterval: 0.5,
            language: .japanese
        )

        XCTAssertEqual(subtitles.count, 2)
        XCTAssertLessThan(subtitles[0].endTime, subtitles[1].startTime)
    }

    func testNativeOCRMergeFrameTextsPadsTimingForSampleInterval() {
        let subtitles = NativeOCRExtractor.mergeFrameTexts(
            [
                (time: 1.0, text: "字幕テスト"),
                (time: 1.5, text: "字幕テスト"),
            ],
            sampleInterval: 0.5,
            language: .japanese
        )

        XCTAssertEqual(subtitles.count, 1)
        XCTAssertEqual(subtitles[0].startTime, 0.75, accuracy: 0.001)
        XCTAssertEqual(subtitles[0].endTime, 1.75, accuracy: 0.001)
    }

    func testPersistentAppStateStoresWorkspaceLayoutPreset() throws {
        var state = PersistentAppState()
        state.workspaceLayoutPreset = .editorFocus
        state.appLanguage = .english
        state.ocrRefinementMode = .aggressive
        state.useContextualTranslation = true
        state.translationContextWindow = 3
        state.preserveSlangAndTone = false
        state.sharePreReleaseAnalytics = true
        state.includeDiagnosticsInFeedback = false
        state.preferredVisionModel = "qwen2.5vl"
        state.importedFontPaths = ["/tmp/FontA.otf", "/tmp/FontB.ttf"]

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistentAppState.self, from: encoded)

        XCTAssertEqual(decoded.workspaceLayoutPreset, .editorFocus)
        XCTAssertEqual(decoded.appLanguage, .english)
        XCTAssertEqual(decoded.ocrRefinementMode, .aggressive)
        XCTAssertTrue(decoded.useContextualTranslation)
        XCTAssertEqual(decoded.translationContextWindow, 3)
        XCTAssertFalse(decoded.preserveSlangAndTone)
        XCTAssertTrue(decoded.sharePreReleaseAnalytics)
        XCTAssertFalse(decoded.includeDiagnosticsInFeedback)
        XCTAssertEqual(decoded.preferredVisionModel, "qwen2.5vl")
        XCTAssertEqual(decoded.importedFontPaths, ["/tmp/FontA.otf", "/tmp/FontB.ttf"])
    }

    func testPersistentAppStateStoresUpdatePreferences() throws {
        var state = PersistentAppState()
        state.automaticallyChecksForUpdates = false
        state.automaticallyDownloadsUpdates = true
        state.includePrereleaseUpdates = true
        state.updateCheckInterval = .weekly
        state.lastUpdateCheckAt = Date(timeIntervalSince1970: 1_700_000_000)
        state.dismissedUpdateVersion = "1.1.0"
        state.downloadedUpdateVersion = "1.2.0"
        state.downloadedUpdatePath = "/tmp/CaptionStudio-macOS.pkg"

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistentAppState.self, from: encoded)

        XCTAssertFalse(decoded.automaticallyChecksForUpdates)
        XCTAssertTrue(decoded.automaticallyDownloadsUpdates)
        XCTAssertTrue(decoded.includePrereleaseUpdates)
        XCTAssertEqual(decoded.updateCheckInterval, .weekly)
        XCTAssertEqual(decoded.dismissedUpdateVersion, "1.1.0")
        XCTAssertEqual(decoded.downloadedUpdateVersion, "1.2.0")
        XCTAssertEqual(decoded.downloadedUpdatePath, "/tmp/CaptionStudio-macOS.pkg")
        XCTAssertNotNil(decoded.lastUpdateCheckAt)
        XCTAssertEqual(decoded.lastUpdateCheckAt!.timeIntervalSince1970, 1_700_000_000, accuracy: 0.1)
    }

    func testPersistentStateStoreRoundTripUsesApplicationSupportFile() throws {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let previousOverride = getenv("CAPTIONSTUDIO_APP_SUPPORT_DIR_OVERRIDE").map { String(cString: $0) }
        setenv("CAPTIONSTUDIO_APP_SUPPORT_DIR_OVERRIDE", workingDirectory.path, 1)
        defer {
            if let previousOverride {
                setenv("CAPTIONSTUDIO_APP_SUPPORT_DIR_OVERRIDE", previousOverride, 1)
            } else {
                unsetenv("CAPTIONSTUDIO_APP_SUPPORT_DIR_OVERRIDE")
            }
            try? PersistentStateStore.clear()
            try? FileManager.default.removeItem(at: workingDirectory)
        }

        var state = PersistentAppState()
        state.appLanguage = .korean
        state.captionStylePreset = .youtube
        state.overlayTolerance = 0.22
        state.overlayPresets = [
            OverlayPreset(
                name: "Overlay A",
                path: "/tmp/overlay-a.png",
                keyColor: .greenScreen,
                tolerance: 0.22,
                softness: 0.09,
                videoRect: NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.7),
                videoOffset: SavedSize(),
                videoZoom: 1.0,
                subtitleRect: NormalizedRect(x: 0.1, y: 0.8, width: 0.8, height: 0.12)
            ),
        ]

        try PersistentStateStore.save(state)
        let restored = try PersistentStateStore.load()

        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.appLanguage, .korean)
        XCTAssertEqual(restored?.captionStylePreset, .youtube)
        XCTAssertEqual(restored?.overlayTolerance ?? 0.0, 0.22, accuracy: 0.0001)
        XCTAssertEqual(restored?.overlayPresets.first?.name, "Overlay A")
        XCTAssertTrue(FileManager.default.fileExists(atPath: PersistentStateStore.fileURL().path))
    }

    func testUpdateCheckerPrefersPkgAssetFromGitHubRelease() throws {
        let payload = """
        {
          "tag_name": "v1.2.0",
          "name": "Caption Studio 1.2.0",
          "body": "Release notes",
          "html_url": "https://example.com/release",
          "published_at": "2026-03-11T01:30:00Z",
          "draft": false,
          "prerelease": false,
          "assets": [
            {
              "name": "CaptionStudio-macOS.zip",
              "content_type": "application/zip",
              "size": 12345,
              "digest": "sha256:1111",
              "browser_download_url": "https://example.com/download.zip",
              "state": "uploaded"
            },
            {
              "name": "CaptionStudio-macOS.pkg",
              "content_type": "application/octet-stream",
              "size": 45678,
              "digest": "sha256:2222",
              "browser_download_url": "https://example.com/download.pkg",
              "state": "uploaded"
            }
          ]
        }
        """

        let update = try XCTUnwrap(
            UpdateChecker.updateInfo(from: Data(payload.utf8), currentVersion: "1.0.0")
        )

        XCTAssertEqual(update.version, "1.2.0")
        XCTAssertEqual(update.preferredDownloadAsset?.name, "CaptionStudio-macOS.pkg")
        XCTAssertEqual(update.installerAsset?.downloadURL.absoluteString, "https://example.com/download.pkg")
    }

    func testUpdateCheckerIncludesPrereleaseWhenEnabled() throws {
        let payload = """
        [
          {
            "tag_name": "v1.0.4-beta.2",
            "name": "Caption Studio 1.0.4 Beta 2",
            "body": "Beta notes",
            "html_url": "https://example.com/beta",
            "published_at": "2026-03-16T01:30:00Z",
            "draft": false,
            "prerelease": true,
            "assets": [
              {
                "name": "CaptionStudio-1.0.4-beta.2-macOS.pkg",
                "content_type": "application/octet-stream",
                "size": 45678,
                "digest": "sha256:beta",
                "browser_download_url": "https://example.com/beta.pkg",
                "state": "uploaded"
              }
            ]
          },
          {
            "tag_name": "v1.0.3",
            "name": "Caption Studio 1.0.3",
            "body": "Stable notes",
            "html_url": "https://example.com/stable",
            "published_at": "2026-03-12T01:30:00Z",
            "draft": false,
            "prerelease": false,
            "assets": [
              {
                "name": "CaptionStudio-1.0.3-macOS.pkg",
                "content_type": "application/octet-stream",
                "size": 45678,
                "digest": "sha256:stable",
                "browser_download_url": "https://example.com/stable.pkg",
                "state": "uploaded"
              }
            ]
          }
        ]
        """

        let update = try XCTUnwrap(
            UpdateChecker.updateInfo(
                from: Data(payload.utf8),
                currentVersion: "1.0.3",
                includePrerelease: true
            )
        )

        XCTAssertEqual(update.version, "1.0.4-beta.2")
        XCTAssertEqual(update.releasePageURL.absoluteString, "https://example.com/beta")
    }

    func testUpdateCheckerIgnoresPrereleaseWhenDisabled() throws {
        let payload = """
        [
          {
            "tag_name": "v1.0.4-beta.2",
            "name": "Caption Studio 1.0.4 Beta 2",
            "body": "Beta notes",
            "html_url": "https://example.com/beta",
            "published_at": "2026-03-16T01:30:00Z",
            "draft": false,
            "prerelease": true,
            "assets": []
          },
          {
            "tag_name": "v1.0.3",
            "name": "Caption Studio 1.0.3",
            "body": "Stable notes",
            "html_url": "https://example.com/stable",
            "published_at": "2026-03-12T01:30:00Z",
            "draft": false,
            "prerelease": false,
            "assets": []
          }
        ]
        """

        let update = try UpdateChecker.updateInfo(
            from: Data(payload.utf8),
            currentVersion: "1.0.3",
            includePrerelease: false
        )

        XCTAssertNil(update)
    }

    func testUpdateCheckerSemverComparisonHandlesPrereleaseOrdering() {
        XCTAssertEqual(UpdateChecker.compareVersions("1.0.4-beta.10", "1.0.4-beta.2"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("1.0.4", "1.0.4-rc.1"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("1.0.4-rc.1", "1.0.4-beta.9"), .orderedDescending)
    }

    @MainActor
    func testNativeOCRExtractorRecognizesEnglishVideo() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("english_subtitle.mov")
        try makeTextVideo(
            url: inputURL,
            size: CGSize(width: 640, height: 360),
            fps: 6,
            frameCount: 12,
            text: "Hello subtitle"
        )

        let payload = try await NativeOCRExtractor.extract(
            videoURL: inputURL,
            region: NormalizedRect(x: 0.08, y: 0.68, width: 0.84, height: 0.20),
            preferences: ProcessingPreferences(
                fpsSample: 2.0,
                detectScroll: false,
                minDuration: 0.4,
                maxDuration: 4.0,
                subtitleLanguage: "en",
                wrapWidthRatio: 0.68,
                subtitleFontSize: 24,
                subtitleFontName: "Hiragino Sans",
                subtitleOutlineWidth: 4.0
            ),
            language: .english
        )

        XCTAssertFalse(payload.subtitles.isEmpty)
        XCTAssertTrue(
            payload.subtitles.contains { subtitle in
                subtitle.text.localizedCaseInsensitiveContains("hello")
            }
        )
    }

    @MainActor
    func testNativeOCRExtractorRecognizesChineseAndKoreanVideo() async throws {
        try await assertNativeOCRRecognition(text: "字幕测试", language: .chinese, expectedFragment: "字幕")
        try await assertNativeOCRRecognition(text: "자막 테스트", language: .korean, expectedFragment: "자막")
    }

    func testNativeOCRExtractorClampsLastSampleBeforeVideoEnd() {
        let duration = 56.318666666666665
        let sampleInterval = 0.5

        let total = NativeOCRExtractor.sampleCount(duration: duration, sampleInterval: sampleInterval)
        let lastTimestamp = NativeOCRExtractor.sampleTimestamp(
            for: total - 1,
            sampleInterval: sampleInterval,
            duration: duration
        )

        XCTAssertEqual(total, 113)
        XCTAssertLessThan(lastTimestamp, duration)
        XCTAssertEqual(lastTimestamp, 56.0, accuracy: 0.0001)
    }

    func testNativeOCRFrameReadCandidateTimesIncludeNearbyFramesAtStart() {
        let candidates = NativeOCRExtractor.frameReadCandidateTimes(
            requestedTime: 0.0,
            duration: 72.833,
            frameDuration: 1.0 / 30.0
        )

        XCTAssertNotNil(candidates.first)
        XCTAssertEqual(candidates.first ?? 0.0, 0.0, accuracy: 0.0001)
        XCTAssertTrue(candidates.contains(where: { abs($0 - (1.0 / 30.0)) < 0.0001 }))
        XCTAssertTrue(candidates.allSatisfy { $0 >= 0.0 })
    }

    func testNativeOCRFrameReadCandidateTimesClampNearVideoEnd() {
        let duration = 72.833
        let candidates = NativeOCRExtractor.frameReadCandidateTimes(
            requestedTime: duration,
            duration: duration,
            frameDuration: 1.0 / 30.0
        )

        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy { $0 < duration })
    }

    func testNativeOCRScriptCoveragePrefersExpectedLanguage() {
        let koreanScore = NativeOCRExtractor.scriptCoverageScore(for: "자막 테스트", language: .korean)
        let koreanMismatch = NativeOCRExtractor.scriptCoverageScore(for: "subtitle test", language: .korean)
        let chineseScore = NativeOCRExtractor.scriptCoverageScore(for: "字幕测试", language: .chinese)
        let chineseMismatch = NativeOCRExtractor.scriptCoverageScore(for: "subtitle test", language: .chinese)
        let englishScore = NativeOCRExtractor.scriptCoverageScore(for: "subtitle test", language: .english)
        let englishMismatch = NativeOCRExtractor.scriptCoverageScore(for: "자막 테스트", language: .english)

        XCTAssertGreaterThan(koreanScore, koreanMismatch)
        XCTAssertGreaterThan(chineseScore, chineseMismatch)
        XCTAssertGreaterThan(englishScore, englishMismatch)
    }

    func testNativeOCRSanitizeRecognizedTextRemovesEmojiArtifacts() {
        let sanitized = NativeOCRExtractor.sanitizeRecognizedText(
            "🎉 자막 테스트 ✨\n😀字幕测试⭐️\nHello 😊 subtitle",
            language: .korean
        )

        XCTAssertFalse(sanitized.contains("🎉"))
        XCTAssertFalse(sanitized.contains("✨"))
        XCTAssertFalse(sanitized.contains("⭐️"))
        XCTAssertTrue(sanitized.contains("자막 테스트"))
        XCTAssertTrue(sanitized.contains("字幕测试"))
        XCTAssertTrue(sanitized.contains("Hello subtitle"))
    }

    @MainActor
    func testRecommendedTranslationModelUsesInstalledTaggedModel() {
        let viewModel = AppViewModel()
        viewModel.availableTranslationModels = ["translategemma:2b", "qwen2.5vl:7b"]
        viewModel.translationModel = "gemma3:4b"

        viewModel.installRecommendedOllamaModel(
            OllamaModelRecommendation(
                modelName: "translategemma",
                purpose: .translation,
                focusLanguage: .english
            )
        )

        XCTAssertEqual(viewModel.translationModel, "translategemma:2b")
    }

    @MainActor
    func testRecommendedVisionModelDoesNotReplaceTranslationModel() {
        let viewModel = AppViewModel()
        viewModel.availableTranslationModels = ["gemma3:4b", "qwen2.5vl:7b"]
        viewModel.translationModel = "gemma3:4b"

        viewModel.installRecommendedOllamaModel(
            OllamaModelRecommendation(
                modelName: "qwen2.5vl",
                purpose: .visionOCR,
                focusLanguage: .korean
            )
        )

        XCTAssertEqual(viewModel.translationModel, "gemma3:4b")
        XCTAssertEqual(viewModel.preferredVisionModel, "qwen2.5vl:7b")
    }

    @MainActor
    func testUpdateSubtitleStartKeepsSelection() {
        let viewModel = AppViewModel()
        let first = SubtitleItem(index: 1, startTime: 0.8, endTime: 1.8, text: "A")
        let second = SubtitleItem(index: 2, startTime: 2.2, endTime: 3.0, text: "B")
        viewModel.subtitles = [first, second]
        viewModel.selectedSubtitleID = first.id

        viewModel.updateSubtitleStart(id: first.id, to: 0.4)

        XCTAssertEqual(viewModel.selectedSubtitleID, first.id)
        XCTAssertEqual(viewModel.subtitles.first?.startTime ?? 0.0, 0.4, accuracy: 0.001)
    }

    @MainActor
    func testUpdateSubtitleEndClampsToMinimumDuration() {
        let viewModel = AppViewModel()
        let subtitle = SubtitleItem(index: 1, startTime: 1.0, endTime: 2.0, text: "A")
        viewModel.subtitles = [subtitle]
        viewModel.selectedSubtitleID = subtitle.id

        viewModel.updateSubtitleEnd(id: subtitle.id, to: 1.1)

        XCTAssertEqual(viewModel.subtitles.first?.endTime ?? 0.0, 1.5, accuracy: 0.001)
        XCTAssertEqual(viewModel.selectedSubtitleID, subtitle.id)
    }

    @MainActor
    func testMoveSubtitlePreservesDurationAndSelection() {
        let viewModel = AppViewModel()
        let subtitle = SubtitleItem(index: 1, startTime: 1.0, endTime: 2.2, text: "A")
        viewModel.subtitles = [subtitle]
        viewModel.selectedSubtitleID = subtitle.id

        viewModel.moveSubtitle(id: subtitle.id, toStartTime: 2.0)

        XCTAssertEqual(viewModel.subtitles.first?.startTime ?? 0.0, 2.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.subtitles.first?.endTime ?? 0.0, 3.2, accuracy: 0.001)
        XCTAssertEqual(viewModel.selectedSubtitleID, subtitle.id)
    }

    @MainActor
    func testMoveSubtitleSnapsToNearbyBoundary() {
        let viewModel = AppViewModel()
        let first = SubtitleItem(index: 1, startTime: 0.0, endTime: 2.0, text: "A")
        let second = SubtitleItem(index: 2, startTime: 3.0, endTime: 4.0, text: "B")
        viewModel.subtitles = [first, second]
        viewModel.selectedSubtitleID = second.id

        viewModel.moveSubtitle(id: second.id, toStartTime: 2.08)

        XCTAssertEqual(viewModel.subtitles[1].startTime, 2.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.subtitles[1].endTime, 3.0, accuracy: 0.001)
    }

    @MainActor
    func testMoveSelectedSubtitlesPreservesRelativeOffsets() {
        let viewModel = AppViewModel()
        let first = SubtitleItem(index: 1, startTime: 1.0, endTime: 2.0, text: "A")
        let second = SubtitleItem(index: 2, startTime: 2.5, endTime: 3.0, text: "B")
        let third = SubtitleItem(index: 3, startTime: 5.0, endTime: 6.0, text: "C")
        viewModel.subtitles = [first, second, third]
        viewModel.setSelectedSubtitleIDs([first.id, second.id], primary: second.id, seek: false)

        viewModel.moveSelectedSubtitles(anchorID: second.id, toStartTime: 4.0)

        XCTAssertEqual(viewModel.subtitles[0].startTime, 2.5, accuracy: 0.001)
        XCTAssertEqual(viewModel.subtitles[1].startTime, 4.0, accuracy: 0.001)
        XCTAssertEqual(
            viewModel.subtitles[1].startTime - viewModel.subtitles[0].startTime,
            1.5,
            accuracy: 0.001
        )
        XCTAssertEqual(viewModel.selectedSubtitleIDs, Set([first.id, second.id]))
        XCTAssertEqual(viewModel.selectedSubtitleID, second.id)
    }

    @MainActor
    func testUpdateSelectedSubtitlesStartAdjustsEarliestBoundary() {
        let viewModel = AppViewModel()
        let first = SubtitleItem(index: 1, startTime: 1.0, endTime: 2.0, text: "A")
        let second = SubtitleItem(index: 2, startTime: 2.5, endTime: 3.0, text: "B")
        let third = SubtitleItem(index: 3, startTime: 5.0, endTime: 6.0, text: "C")
        viewModel.subtitles = [first, second, third]
        viewModel.setSelectedSubtitleIDs([first.id, second.id], primary: second.id, seek: false)

        viewModel.updateSelectedSubtitlesStart(to: 0.6)

        XCTAssertEqual(viewModel.subtitles[0].startTime, 0.6, accuracy: 0.001)
        XCTAssertEqual(viewModel.subtitles[1].startTime, 2.5, accuracy: 0.001)
        XCTAssertEqual(viewModel.selectedSubtitleIDs, Set([first.id, second.id]))
        XCTAssertEqual(viewModel.selectedSubtitleID, second.id)
    }

    @MainActor
    func testUpdateSelectedSubtitlesEndAdjustsLatestBoundary() {
        let viewModel = AppViewModel()
        let first = SubtitleItem(index: 1, startTime: 1.0, endTime: 2.0, text: "A")
        let second = SubtitleItem(index: 2, startTime: 2.5, endTime: 3.0, text: "B")
        let third = SubtitleItem(index: 3, startTime: 5.0, endTime: 6.0, text: "C")
        viewModel.subtitles = [first, second, third]
        viewModel.setSelectedSubtitleIDs([first.id, second.id], primary: first.id, seek: false)

        viewModel.updateSelectedSubtitlesEnd(to: 3.4)

        XCTAssertEqual(viewModel.subtitles[0].endTime, 2.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.subtitles[1].endTime, 3.4, accuracy: 0.001)
        XCTAssertEqual(viewModel.selectedSubtitleIDs, Set([first.id, second.id]))
        XCTAssertEqual(viewModel.selectedSubtitleID, first.id)
    }

    @MainActor
    func testApplySelectedSubtitleEditsPreservesManualGap() {
        let viewModel = AppViewModel()
        let first = SubtitleItem(index: 1, startTime: 1.0, endTime: 2.0, text: "A")
        let second = SubtitleItem(index: 2, startTime: 3.0, endTime: 4.0, text: "B")
        viewModel.subtitles = [first, second]
        viewModel.selectedSubtitleID = first.id

        viewModel.applySelectedSubtitleEdits(
            startText: "00:00:01.20",
            endText: "00:00:02.20",
            originalText: "A",
            translatedText: ""
        )

        XCTAssertEqual(viewModel.subtitles[0].startTime, 1.2, accuracy: 0.001)
        XCTAssertEqual(viewModel.subtitles[0].endTime, 2.2, accuracy: 0.001)
        XCTAssertEqual(viewModel.subtitles[1].startTime, 3.0, accuracy: 0.001)
    }

    @MainActor
    func testDuplicateSelectedSubtitlesPreservesRelativeOffsets() {
        let viewModel = AppViewModel()
        let first = SubtitleItem(index: 1, startTime: 1.0, endTime: 2.0, text: "A")
        let second = SubtitleItem(index: 2, startTime: 2.5, endTime: 3.0, text: "B")
        let third = SubtitleItem(index: 3, startTime: 5.0, endTime: 6.0, text: "C")
        viewModel.subtitles = [first, second, third]
        viewModel.setSelectedSubtitleIDs([first.id, second.id], primary: first.id, seek: false)

        viewModel.duplicateSelectedSubtitles()

        XCTAssertEqual(viewModel.subtitles.count, 5)
        let duplicated = viewModel.subtitles.suffix(2)
        XCTAssertEqual(duplicated.first?.text, "A")
        XCTAssertEqual(duplicated.last?.text, "B")
        XCTAssertEqual((duplicated.last?.startTime ?? 0) - (duplicated.first?.startTime ?? 0), 1.5, accuracy: 0.001)
        XCTAssertEqual(viewModel.selectedSubtitleIDs.count, 2)
    }

    @MainActor
    func testCreateSubtitleSelectsInsertedRange() {
        let viewModel = AppViewModel()
        let first = SubtitleItem(index: 1, startTime: 0.0, endTime: 1.0, text: "A")
        viewModel.subtitles = [first]

        viewModel.createSubtitle(startTime: 1.4, endTime: 2.1, text: "New")

        XCTAssertEqual(viewModel.subtitles.count, 2)
        XCTAssertEqual(viewModel.subtitles.last?.text, "New")
        XCTAssertEqual(viewModel.subtitles.last?.startTime ?? 0, 1.4, accuracy: 0.001)
        XCTAssertEqual(viewModel.subtitles.last?.endTime ?? 0, 2.1, accuracy: 0.001)
        XCTAssertEqual(viewModel.selectedSubtitleIDs.count, 1)
        XCTAssertEqual(viewModel.selectedSubtitleID, viewModel.subtitles.last?.id)
    }

    @MainActor
    func testSetSelectedSubtitleIDsKeepsPrimaryIfStillIncluded() {
        let viewModel = AppViewModel()
        let first = SubtitleItem(index: 1, startTime: 0.0, endTime: 1.0, text: "A")
        let second = SubtitleItem(index: 2, startTime: 1.2, endTime: 2.0, text: "B")
        let third = SubtitleItem(index: 3, startTime: 2.2, endTime: 3.0, text: "C")
        viewModel.subtitles = [first, second, third]
        viewModel.selectedSubtitleID = second.id

        viewModel.setSelectedSubtitleIDs([first.id, second.id, third.id], primary: nil, seek: false)

        XCTAssertEqual(viewModel.selectedSubtitleID, second.id)
        XCTAssertEqual(viewModel.selectedSubtitleIDs, Set([first.id, second.id, third.id]))
    }

    @MainActor
    func testDeleteSelectedSubtitleRemovesMultipleSubtitles() {
        let viewModel = AppViewModel()
        let first = SubtitleItem(index: 1, startTime: 0.0, endTime: 1.0, text: "A")
        let second = SubtitleItem(index: 2, startTime: 1.2, endTime: 2.0, text: "B")
        let third = SubtitleItem(index: 3, startTime: 2.2, endTime: 3.0, text: "C")
        viewModel.subtitles = [first, second, third]
        viewModel.setSelectedSubtitleIDs([first.id, second.id], primary: second.id, seek: false)

        viewModel.deleteSelectedSubtitle()

        XCTAssertEqual(viewModel.subtitles.map(\.id), [third.id])
        XCTAssertEqual(viewModel.selectedSubtitleID, third.id)
        XCTAssertEqual(viewModel.selectedSubtitleIDs, [third.id])
    }

    func testProjectDocumentRoundTripPreservesSelectedSubtitleIDs() throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ProductConstants.projectFileExtension)
        let state = PersistentAppState()
        let selectedIDs = [UUID(), UUID()]
        let document = SubtitleProjectDocument(
            savedAt: Date(timeIntervalSince1970: 1_700_000_100),
            videoPath: "/tmp/example.mov",
            subtitles: [],
            selectedSubtitleID: selectedIDs.last,
            selectedSubtitleIDs: selectedIDs,
            persistentState: state
        )

        try ProjectStore.save(document, to: temporaryURL)
        let loaded = try ProjectStore.load(from: temporaryURL)

        XCTAssertEqual(loaded.selectedSubtitleID, selectedIDs.last)
        XCTAssertEqual(loaded.selectedSubtitleIDs ?? [], selectedIDs)
    }

    @MainActor
    func testFeedbackServiceCreatesArchive() throws {
        let context = FeedbackReportContext(
            appVersion: "1.0.0",
            buildNumber: "1",
            appLanguage: "en",
            subtitleLanguage: "ko",
            translationTargetLanguage: "ja",
            translationModel: "translategemma:2b",
            preferredVisionModel: "qwen2.5vl:7b",
            ollamaAvailable: true,
            currentVideoName: "sample.mp4",
            currentProjectName: "sample.subtitleproject",
            latestStatusMessage: "Ready",
            latestErrorMessage: nil,
            sharePreReleaseAnalytics: true,
            includeDiagnosticsInFeedback: true,
            workspaceLayout: WorkspaceLayoutPreset.balanced.rawValue,
            timestamp: Date(),
            osVersion: "macOS",
            recentLogs: [
                FeedbackLogEntry(level: .error, message: "Example error")
            ]
        )
        let draft = FeedbackDraft(
            category: .bug,
            message: "Sample feedback",
            includeScreenshot: false,
            includeDiagnostics: true
        )

        let archiveURL = try FeedbackService.createArchive(
            context: context,
            draft: draft,
            window: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertEqual(archiveURL.pathExtension, "zip")
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

    @MainActor
    private func assertNativeOCRRecognition(
        text: String,
        language: TranslationLanguage,
        expectedFragment: String
    ) async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let inputURL = tempDirectory.appendingPathComponent("\(language.rawValue).mov")
        try makeTextVideo(
            url: inputURL,
            size: CGSize(width: 640, height: 360),
            fps: 6,
            frameCount: 12,
            text: text
        )

        let payload = try await NativeOCRExtractor.extract(
            videoURL: inputURL,
            region: NormalizedRect(x: 0.08, y: 0.68, width: 0.84, height: 0.20),
            preferences: ProcessingPreferences(
                fpsSample: 2.0,
                detectScroll: false,
                minDuration: 0.4,
                maxDuration: 4.0,
                subtitleLanguage: language.rawValue,
                wrapWidthRatio: 0.68,
                subtitleFontSize: 24,
                subtitleFontName: "Hiragino Sans",
                subtitleOutlineWidth: 4.0
            ),
            language: language
        )

        XCTAssertFalse(payload.subtitles.isEmpty)
        XCTAssertTrue(
            payload.subtitles.contains { subtitle in
                subtitle.text.contains(expectedFragment)
            }
        )
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

    private func makeTextVideo(url: URL, size: CGSize, fps: Int32, frameCount: Int, text: String) throws {
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

            guard let pixelBuffer = makeTextPixelBuffer(
                size: size,
                text: text,
                backgroundColor: frameIndex.isMultiple(of: 2)
                    ? NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1.0)
                    : NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.26, alpha: 1.0)
            ) else {
                XCTFail("Failed to create text pixel buffer")
                return
            }

            let time = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: time))
        }

        input.markAsFinished()
        let finishExpectation = expectation(description: "finishTextVideo")
        writer.finishWriting {
            finishExpectation.fulfill()
        }
        wait(for: [finishExpectation], timeout: 10.0)
        XCTAssertEqual(writer.status, .completed)
    }

    private func makePixelBuffer(size: CGSize, color: NSColor) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]

        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            pixelBufferAttributes as CFDictionary,
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

    private func makeTextPixelBuffer(size: CGSize, text: String, backgroundColor: NSColor) -> CVPixelBuffer? {
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

        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        let bannerRect = CGRect(x: 50, y: 34, width: size.width - 100, height: 92)
        NSColor(calibratedWhite: 0.97, alpha: 0.95).setFill()
        NSBezierPath(roundedRect: bannerRect, xRadius: 18, yRadius: 18).fill()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 42, weight: .bold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle,
        ]

        let string = NSAttributedString(string: text, attributes: textAttributes)
        let textRect = CGRect(x: 70, y: 54, width: size.width - 140, height: 56)
        string.draw(
            with: textRect,
            options: NSString.DrawingOptions([.usesLineFragmentOrigin, .usesFontLeading])
        )

        NSGraphicsContext.restoreGraphicsState()
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
