import AVKit
import AppKit
import Combine
import CoreText
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var videoURL: URL?
    @Published var videoMetadata: VideoMetadata?
    @Published var previewImage: NSImage?
    @Published var subtitleRegion: NormalizedRect = .defaultSubtitleArea
    @Published var subtitles: [SubtitleItem] = []
    @Published var selectedSubtitleID: SubtitleItem.ID?
    @Published var isBusy = false
    @Published var statusMessage = "動画を開いて、字幕範囲をドラッグで指定してください。"
    @Published var backendSummary = "Python 環境を確認中…"
    @Published var errorMessage: String?

    @Published var fpsSample: Double = 2.0
    @Published var detectScroll = true
    @Published var minDuration: Double = 0.5
    @Published var maxDuration: Double = 10.0
    @Published var wrapWidthRatio: Double = 0.68
    @Published var subtitleFontSize: Double = 24.0
    @Published var subtitleFontName: String
    @Published var subtitleOutlineWidth: Double = 4.0

    @Published var exportFormat: ExportFormat = .srt
    @Published var exportTextMode: ExportTextMode = .translated

    @Published var translationModel = "gemma3:4b"
    @Published var sourceLanguage = "ja"
    @Published var targetLanguage = "en"
    @Published var dictionaryEntries: [DictionaryEntry] = []
    @Published var extractionProgress: ExtractionProgress?

    @Published var overlayOriginalImage: NSImage?
    @Published var overlayProcessedImage: NSImage?
    @Published var overlayFileName = ""
    @Published var overlayKeyColor: RGBColor = .greenScreen {
        didSet { refreshOverlayProcessingIfNeeded() }
    }
    @Published var overlayTolerance: Double = 0.16 {
        didSet { refreshOverlayProcessingIfNeeded() }
    }
    @Published var overlaySoftness: Double = 0.08 {
        didSet { refreshOverlayProcessingIfNeeded() }
    }
    @Published var overlayVideoRect = NormalizedRect(x: 0.08, y: 0.08, width: 0.84, height: 0.72)
    @Published var overlayVideoOffset = CGSize.zero
    @Published var overlayVideoZoom: Double = 1.0
    @Published var subtitleLayoutRect = NormalizedRect(x: 0.08, y: 0.86, width: 0.84, height: 0.10)
    @Published var additionalSubtitleLayoutRect = NormalizedRect.defaultAdditionalBannerArea
    @Published var overlayEditMode: OverlayEditMode = .videoPosition
    @Published var availableFontNames: [String] = []
    @Published var importedFontFiles: [URL] = []
    @Published var favoriteFontNames: [String] = []
    @Published var overlayPresets: [OverlayPreset] = []
    @Published var playbackTime: Double = 0.0
    @Published var playbackScrubTime: Double = 0.0
    @Published var isScrubbingPlayback = false

    private let backend = PythonBackendBridge()
    private var overlayProcessingTask: Task<Void, Never>?
    private var overlayVideoRectIsManual = false
    private let importedFontsDefaultsKey = "SubtitleExtractorMacApp.importedFonts"
    private let persistentStateDefaultsKey = "SubtitleExtractorMacApp.persistentState"
    private var currentOverlayURL: URL?
    private var cancellables = Set<AnyCancellable>()
    private var suppressPersistence = true
    private var playerTimeObserver: Any?

    init() {
        _subtitleFontName = Published(
            initialValue: "Hiragino Sans"
        )
        restoreImportedFonts()
        refreshAvailableFonts(preferredSelection: nil)
        restorePersistentState()
        setupPersistence()
        suppressPersistence = false
        refreshRuntimeStatus()
    }

    var selectedSubtitle: SubtitleItem? {
        guard let selectedSubtitleID else {
            return nil
        }
        return subtitles.first(where: { $0.id == selectedSubtitleID })
    }

    var playbackMatchedSubtitle: SubtitleItem? {
        SubtitleUtilities.subtitle(containing: displayedPlaybackTime, in: subtitles)
    }

    var activePreviewSubtitle: SubtitleItem? {
        if let playbackMatchedSubtitle {
            return playbackMatchedSubtitle
        }

        if isScrubbingPlayback || player?.timeControlStatus == .playing {
            return nil
        }

        return selectedSubtitle ?? subtitles.first
    }

    var subtitleSummary: String {
        guard !subtitles.isEmpty else {
            return "字幕はまだありません"
        }

        let translatedCount = subtitles.filter { !$0.translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        return "\(subtitles.count)件 / 翻訳済み \(translatedCount)件"
    }

    var previewWrappedText: String {
        previewSubtitleLayout.text
    }

    var previewSubtitleImage: NSImage? {
        let layout = previewSubtitleLayout
        guard !layout.text.isEmpty else {
            return nil
        }

        let regionSize = previewSubtitleRenderSize
        guard let cgImage = SubtitleUtilities.subtitleImage(
            text: layout.text,
            size: regionSize,
            fontName: subtitleFontName,
            fontSize: CGFloat(layout.fontSize),
            outlineWidth: CGFloat(layout.outlineWidth)
        ) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: regionSize.width, height: regionSize.height))
    }

    var previewAdditionalSubtitleImage: NSImage? {
        let layout = previewAdditionalSubtitleLayout
        guard !layout.text.isEmpty else {
            return nil
        }

        let regionSize = additionalSubtitleRenderSize
        guard let cgImage = SubtitleUtilities.additionalSubtitleBannerImage(
            text: layout.text,
            size: regionSize,
            fontName: subtitleFontName,
            fontSize: CGFloat(layout.fontSize),
            backgroundOpacity: 0.78
        ) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: regionSize.width, height: regionSize.height))
    }

    var previewSubtitleLayout: FittedSubtitleLayout {
        guard let activePreviewSubtitle else {
            return .empty
        }

        let sourceText = if exportTextMode == .translated && !activePreviewSubtitle.translated.isEmpty {
            activePreviewSubtitle.translated
        } else {
            activePreviewSubtitle.text
        }

        return SubtitleUtilities.fitSubtitleLayout(
            text: sourceText,
            regionSize: previewSubtitleRenderSize,
            fontName: subtitleFontName,
            preferredFontSize: CGFloat(subtitleFontSize),
            outlineWidth: CGFloat(subtitleOutlineWidth)
        )
    }

    var previewAdditionalSubtitleLayout: FittedSubtitleLayout {
        guard let activePreviewSubtitle else {
            return .empty
        }

        let text = activePreviewSubtitle.additionalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .empty
        }

        return SubtitleUtilities.fitSubtitleLayout(
            text: text,
            regionSize: additionalSubtitleRenderSize,
            fontName: subtitleFontName,
            preferredFontSize: CGFloat(additionalSubtitleFontSize),
            outlineWidth: 0
        )
    }

    var effectiveSubtitleLayoutRect: NormalizedRect {
        if hasOverlay {
            return subtitleLayoutRect
        }
        return NormalizedRect(
            x: max(0.025, (1.0 - wrapWidthRatio) / 2.0),
            y: 0.74,
            width: min(max(wrapWidthRatio, 0.35), 0.95),
            height: 0.18
        ).clamped()
    }

    var extractionProgressValue: Double {
        extractionProgress?.fractionCompleted ?? 0.0
    }

    var extractionProgressText: String {
        guard let extractionProgress else {
            return "抽出待機中"
        }

        let current = SubtitleUtilities.compactTimestamp(extractionProgress.timestamp)
        if let duration = videoMetadata?.duration, duration > 0 {
            let end = SubtitleUtilities.compactTimestamp(duration)
            return "字幕領域をスキャン中: \(current) / \(end)"
        }
        return "字幕領域をスキャン中: \(current)"
    }

    var extractionProgressDetail: String {
        guard let extractionProgress else {
            return "字幕範囲を決めて抽出を開始してください。"
        }
        return "\(extractionProgress.processed) / \(extractionProgress.total) フレームを解析"
    }

    var dictionarySummary: String {
        let count = dictionaryEntries.filter(\.isComplete).count
        return count == 0 ? "辞書未登録" : "\(count)件登録"
    }

    var overlaySummary: String {
        overlayFileName.isEmpty ? "オーバーレイ未設定" : overlayFileName
    }

    var selectedSubtitleSignature: String {
        guard let subtitle = selectedSubtitle else {
            return ""
        }
        return [
            subtitle.id.uuidString,
            String(subtitle.index),
            String(format: "%.3f", subtitle.startTime),
            String(format: "%.3f", subtitle.endTime),
            subtitle.text,
            subtitle.translated,
            subtitle.additionalText,
        ].joined(separator: "|")
    }

    var hasOverlay: Bool {
        overlayProcessedImage != nil
    }

    var canExtract: Bool {
        videoURL != nil && !isBusy
    }

    var canTranslate: Bool {
        !subtitles.isEmpty && !isBusy
    }

    var canExport: Bool {
        !subtitles.isEmpty && !isBusy
    }

    var canExportVideo: Bool {
        canExport && (videoURL != nil || !(videoMetadata?.path ?? "").isEmpty)
    }

    var additionalSubtitleRect: NormalizedRect {
        additionalSubtitleLayoutRect.clamped()
    }

    var additionalSubtitleFontSize: Double {
        min(max(18.0, subtitleFontSize * 0.92), 34.0)
    }

    var playbackDuration: Double {
        if let seconds = player?.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
            return seconds
        }
        if let duration = videoMetadata?.duration, duration.isFinite, duration > 0 {
            return duration
        }
        return 0.0
    }

    var displayedPlaybackTime: Double {
        isScrubbingPlayback ? playbackScrubTime : playbackTime
    }

    var playbackCurrentTimeText: String {
        SubtitleUtilities.compactTimestamp(displayedPlaybackTime)
    }

    var playbackDurationText: String {
        SubtitleUtilities.compactTimestamp(playbackDuration)
    }

    func clearError() {
        errorMessage = nil
    }

    func addDictionaryEntry() {
        dictionaryEntries.append(DictionaryEntry())
    }

    func isFavoriteFont(_ fontName: String) -> Bool {
        favoriteFontNames.contains(fontName)
    }

    func toggleFavoriteFont(_ fontName: String) {
        if let index = favoriteFontNames.firstIndex(of: fontName) {
            favoriteFontNames.remove(at: index)
        } else {
            favoriteFontNames.append(fontName)
            favoriteFontNames.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }

    func loadOverlayPreset(_ preset: OverlayPreset) {
        loadOverlay(
            from: preset.fileURL,
            storedSettings: preset,
            announceStatus: true
        )
    }

    func saveCurrentOverlayAsPreset() {
        guard let currentOverlayURL else {
            present(message: "先にオーバーレイ画像を読み込んでください。")
            return
        }

        let baseName = currentOverlayURL.deletingPathExtension().lastPathComponent
        let preset = OverlayPreset(
            name: baseName.isEmpty ? "Overlay" : baseName,
            path: currentOverlayURL.path,
            keyColor: overlayKeyColor,
            tolerance: overlayTolerance,
            softness: overlaySoftness,
            videoRect: overlayVideoRect,
            videoOffset: SavedSize(overlayVideoOffset),
            videoZoom: overlayVideoZoom,
            subtitleRect: subtitleLayoutRect,
            additionalSubtitleRect: additionalSubtitleLayoutRect
        )

        if let existingIndex = overlayPresets.firstIndex(where: { $0.path == preset.path }) {
            overlayPresets[existingIndex] = preset
            statusMessage = "オーバーレイ preset を更新しました。"
        } else {
            overlayPresets.append(preset)
            overlayPresets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            statusMessage = "オーバーレイ preset を登録しました。"
        }
    }

    func removeOverlayPreset(id: OverlayPreset.ID) {
        overlayPresets.removeAll { $0.id == id }
    }

    func importCustomFontsPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "ttf") ?? .font,
            UTType(filenameExtension: "otf") ?? .font,
            UTType(filenameExtension: "ttc") ?? .font,
            UTType(filenameExtension: "otc") ?? .font,
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.title = "フォントファイルを読み込む"

        guard panel.runModal() == .OK else {
            return
        }

        let (loadedURLs, failedFiles) = registerFontFiles(panel.urls)

        importedFontFiles.append(contentsOf: loadedURLs)
        importedFontFiles = Array(Set(importedFontFiles)).sorted { $0.lastPathComponent < $1.lastPathComponent }
        persistImportedFonts()
        refreshAvailableFonts(preferredSelection: subtitleFontName)

        if let firstLoaded = loadedURLs.first {
            let postScriptName = CTFontManagerCreateFontDescriptorsFromURL(firstLoaded as CFURL) as? [CTFontDescriptor]
            let preferredName = postScriptName?.compactMap {
                CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String
            }.first
            if let preferredName, availableFontNames.contains(preferredName) {
                subtitleFontName = preferredName
            }
        }

        if !failedFiles.isEmpty {
            present(message: "読み込めなかったフォント: \(failedFiles.joined(separator: ", "))")
        } else if !loadedURLs.isEmpty {
            statusMessage = "フォントを読み込みました。"
        }
    }

    func removeDictionaryEntry(id: DictionaryEntry.ID) {
        dictionaryEntries.removeAll { $0.id == id }
    }

    func openOverlayPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "オーバーレイ画像を選択"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        loadOverlay(from: url, announceStatus: false)
    }

    func clearOverlay() {
        overlayProcessingTask?.cancel()
        currentOverlayURL = nil
        overlayOriginalImage = nil
        overlayProcessedImage = nil
        overlayFileName = ""
        overlayVideoOffset = .zero
        overlayVideoZoom = 1.0
        overlayVideoRect = NormalizedRect(x: 0.08, y: 0.08, width: 0.84, height: 0.72)
        overlayEditMode = .subtitleWindow
        overlayVideoRectIsManual = false
    }

    func autoDetectOverlayKeyColor() {
        guard let overlayOriginalImage,
              let detectedColor = SubtitleUtilities.detectChromaKeyColor(in: overlayOriginalImage) else {
            present(message: "キー色を自動検出できませんでした。")
            return
        }
        overlayKeyColor = detectedColor
    }

    func resetOverlayVideoPlacement() {
        overlayVideoOffset = .zero
        overlayVideoZoom = 1.0
    }

    func resetOverlayVideoWindowToDetected() {
        overlayVideoRectIsManual = false
        refreshOverlayProcessing(forceUpdateWindow: true)
    }

    func updateOverlayVideoOffset(_ offset: CGSize) {
        overlayVideoOffset = CGSize(
            width: min(max(offset.width, -1.2), 1.2),
            height: min(max(offset.height, -1.2), 1.2)
        )
    }

    func updateOverlayVideoRect(_ rect: NormalizedRect) {
        overlayVideoRect = rect.clamped()
        overlayVideoRectIsManual = true
    }

    func updateSubtitleLayoutRect(_ rect: NormalizedRect) {
        subtitleLayoutRect = rect.clamped()
    }

    func updateAdditionalSubtitleLayoutRect(_ rect: NormalizedRect) {
        additionalSubtitleLayoutRect = rect.clamped()
    }

    func handleSelectedSubtitleChange() {
        seekToSelectedSubtitle()
    }

    func selectAdjacentSubtitle(offset: Int) {
        guard !subtitles.isEmpty else {
            return
        }

        guard let currentID = selectedSubtitleID,
              let currentIndex = subtitles.firstIndex(where: { $0.id == currentID }) else {
            selectedSubtitleID = subtitles.first?.id
            seekToSelectedSubtitle()
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), subtitles.count - 1)
        selectedSubtitleID = subtitles[nextIndex].id
        seekToSelectedSubtitle()
    }

    func seekToSelectedSubtitle() {
        guard let subtitle = selectedSubtitle ?? subtitles.first else {
            return
        }

        seekPlayback(to: subtitle.startTime, pauseAfterSeek: true)
    }

    func togglePlayback() {
        guard let player else {
            return
        }

        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    func beginPlaybackScrub() {
        guard player != nil else {
            return
        }
        isScrubbingPlayback = true
        playbackScrubTime = playbackTime
        player?.pause()
    }

    func updatePlaybackScrub(to seconds: Double) {
        playbackScrubTime = clampedPlaybackTime(seconds)
    }

    func commitPlaybackScrub() {
        let targetTime = playbackScrubTime
        isScrubbingPlayback = false
        seekPlayback(to: targetTime, pauseAfterSeek: true)
    }

    func seekPlayback(by delta: Double) {
        seekPlayback(to: displayedPlaybackTime + delta, pauseAfterSeek: true)
    }

    func seekPlayback(to seconds: Double, pauseAfterSeek: Bool) {
        let target = clampedPlaybackTime(seconds)
        playbackTime = target
        playbackScrubTime = target

        guard let player else {
            return
        }

        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        if pauseAfterSeek {
            player.pause()
        }
    }

    func refreshRuntimeStatus() {
        let backend = backend
        Task {
            do {
                let report = try await Task.detached(priority: .utility) {
                    try backend.checkEnvironment()
                }.value
                backendSummary = report.summary
            } catch {
                backendSummary = error.localizedDescription
            }
        }
    }

    func openVideoPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "動画を選択"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        Task {
            await loadVideo(from: url)
        }
    }

    func importSRTPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "srt") ?? .plainText,
            .plainText,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "SRT を読み込む"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        Task {
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try SubtitleUtilities.parseSRT(url: url)
                }.value
                subtitles = normalizedSubtitles(from: parsed)
                selectedSubtitleID = subtitles.first?.id
                statusMessage = "SRT を読み込みました。"
                seekToSelectedSubtitle()
            } catch {
                present(error: error)
            }
        }
    }

    func extractSubtitles() {
        guard let videoURL else {
            present(message: "先に動画を開いてください。")
            return
        }

        let backend = backend
        let region = subtitleRegion.clamped()
        let preferences = processingPreferences

        Task {
            setBusy(true, message: "字幕を抽出しています…")
            extractionProgress = ExtractionProgress(processed: 0, total: 1, timestamp: 0.0)
            defer {
                isBusy = false
                extractionProgress = nil
            }

            do {
                let progressHandler = ExtractionProgressHandlerBox { [weak self] progress in
                    self?.updateExtractionProgress(progress)
                }
                let payload = try await backend.extract(
                    videoURL: videoURL,
                    region: region,
                    preferences: preferences,
                    progressHandler: progressHandler
                )

                subtitles = normalizedSubtitles(
                    from: payload.subtitles,
                    duration: payload.video.duration
                )
                videoMetadata = payload.video
                selectedSubtitleID = subtitles.first?.id
                statusMessage = "字幕抽出が完了しました。"
                seekToSelectedSubtitle()
            } catch {
                present(error: error)
            }
        }
    }

    func translateSubtitles() {
        guard !subtitles.isEmpty else {
            present(message: "翻訳する字幕がありません。")
            return
        }

        let backend = backend
        let currentSubtitles = subtitles
        let preferences = translationPreferences
        let selectedID = selectedSubtitleID

        Task {
            setBusy(true, message: "翻訳中です。Ollama の応答を待っています…")
            defer { isBusy = false }

            do {
                let translated = try await Task.detached(priority: .userInitiated) {
                    try backend.translate(
                        subtitles: currentSubtitles,
                        preferences: preferences
                    )
                }.value

                let oldIDs = Dictionary(
                    uniqueKeysWithValues: currentSubtitles.map {
                        ("\($0.index)|\($0.startTime)|\($0.endTime)", $0.id)
                    }
                )

                var merged = translated
                for index in merged.indices {
                    let key = "\(merged[index].index)|\(merged[index].startTime)|\(merged[index].endTime)"
                    if let id = oldIDs[key],
                       let current = currentSubtitles.first(where: { $0.id == id }) {
                        merged[index].id = id
                        merged[index].additionalText = current.additionalText
                    }
                }

                subtitles = normalizedSubtitles(from: merged)
                if let selectedID, subtitles.contains(where: { $0.id == selectedID }) {
                    selectedSubtitleID = selectedID
                } else {
                    selectedSubtitleID = subtitles.first?.id
                }
                statusMessage = "翻訳が完了しました。"
                seekToSelectedSubtitle()
            } catch {
                present(error: error)
            }
        }
    }

    func exportSubtitles(_ format: ExportFormat? = nil) {
        guard !subtitles.isEmpty else {
            present(message: "書き出す字幕がありません。")
            return
        }

        let chosenFormat = format ?? exportFormat
        exportFormat = chosenFormat

        let panel = NSSavePanel()
        panel.allowedContentTypes = [chosenFormat.contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultExportFilename(for: chosenFormat)
        panel.title = "\(chosenFormat.displayName) を書き出す"

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        let backend = backend
        let exportPreferences = ExportPreferences(format: chosenFormat, textMode: exportTextMode)
        let currentProcessingPreferences = processingPreferences
        let normalized = normalizedSubtitles(from: subtitles)
        let video = currentVideoMetadata
        let sourceVideoURL = videoURL ?? (video.path.isEmpty ? nil : URL(fileURLWithPath: video.path))
        let subtitleRect = effectiveSubtitleLayoutRect
        let overlayImage = overlayProcessedImage
        let outputSize = overlayProcessedImage?.size ?? CGSize(
            width: max(2, video.width),
            height: max(2, video.height)
        )

        Task {
            setBusy(true, message: "\(chosenFormat.displayName) を書き出しています…")
            defer { isBusy = false }

            do {
                if chosenFormat == .mp4 || chosenFormat == .mov {
                    guard let sourceVideoURL else {
                        throw NSError(
                            domain: "SubtitleExtractorMacApp",
                            code: 1003,
                            userInfo: [NSLocalizedDescriptionKey: "動画を書き出すには元の動画を開いた状態にしてください。"]
                        )
                    }

                    let request = VideoRenderRequest(
                        sourceURL: sourceVideoURL,
                        destinationURL: destination,
                        format: chosenFormat,
                        subtitles: normalized,
                        textMode: exportTextMode,
                        subtitleRect: subtitleRect,
                        fontName: subtitleFontName,
                        fontSize: CGFloat(subtitleFontSize),
                        outlineWidth: CGFloat(subtitleOutlineWidth),
                        additionalSubtitleRect: additionalSubtitleRect,
                        additionalSubtitleFontSize: CGFloat(additionalSubtitleFontSize),
                        additionalSubtitleBackgroundOpacity: 0.78,
                        overlayImage: overlayImage,
                        outputSize: outputSize,
                        videoRect: hasOverlay ? overlayVideoRect : nil,
                        videoOffset: overlayVideoOffset,
                        videoZoom: overlayVideoZoom
                    )

                    try await VideoBurnInExporter.export(request)
                } else {
                    try await Task.detached(priority: .userInitiated) {
                        try backend.export(
                            subtitles: normalized,
                            video: video,
                            destination: destination,
                            processingPreferences: currentProcessingPreferences,
                            exportPreferences: exportPreferences
                        )
                    }.value
                }

                subtitles = normalized
                statusMessage = "\(chosenFormat.displayName) を保存しました。"
            } catch {
                present(error: error)
            }
        }
    }

    func normalizeCurrentTimings() {
        subtitles = normalizedSubtitles(from: subtitles)
        statusMessage = "時間重なりを補正しました。"
    }

    func addSubtitle() {
        let anchor = selectedSubtitle ?? subtitles.last
        let start = anchor?.endTime ?? 0.0
        let end = start + max(minDuration, 1.0)
        let subtitle = SubtitleItem(
            index: subtitles.count + 1,
            startTime: start,
            endTime: end,
            text: ""
        )
        subtitles.append(subtitle)
        subtitles = normalizedSubtitles(from: subtitles)
        selectedSubtitleID = subtitles.last?.id
        statusMessage = "字幕を追加しました。"
        seekToSelectedSubtitle()
    }

    func deleteSelectedSubtitle() {
        guard let selectedSubtitleID else {
            return
        }

        subtitles.removeAll { $0.id == selectedSubtitleID }
        subtitles = normalizedSubtitles(from: subtitles)
        self.selectedSubtitleID = subtitles.first?.id
        statusMessage = "字幕を削除しました。"
        seekToSelectedSubtitle()
    }

    func resetSubtitleRegion() {
        subtitleRegion = .defaultSubtitleArea
    }

    func applySelectedSubtitleEdits(
        startText: String,
        endText: String,
        originalText: String,
        translatedText: String,
        additionalText: String
    ) {
        guard let selectedSubtitleID,
              let startTime = SubtitleUtilities.parseTimecode(startText),
              let endTime = SubtitleUtilities.parseTimecode(endText),
              let index = subtitles.firstIndex(where: { $0.id == selectedSubtitleID }) else {
            present(message: "開始時刻と終了時刻を正しく入力してください。")
            return
        }

        subtitles[index].startTime = startTime
        subtitles[index].endTime = endTime
        subtitles[index].text = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        subtitles[index].translated = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        subtitles[index].additionalText = additionalText.trimmingCharacters(in: .whitespacesAndNewlines)
        subtitles = normalizedSubtitles(from: subtitles)
        self.selectedSubtitleID = selectedSubtitleID
        statusMessage = "字幕を更新しました。"
        seekToSelectedSubtitle()
    }

    func makeAdditionalSubtitleDraftTarget() -> AdditionalSubtitleDraftTarget? {
        guard videoURL != nil || previewImage != nil || !subtitles.isEmpty else {
            return nil
        }

        let anchorTime = clampedPlaybackTime(displayedPlaybackTime)
        if let subtitle = SubtitleUtilities.subtitle(containing: anchorTime, in: subtitles) {
            return AdditionalSubtitleDraftTarget(
                subtitleID: subtitle.id,
                subtitleIndex: subtitle.index,
                playbackTime: anchorTime,
                startTime: subtitle.startTime,
                endTime: subtitle.endTime,
                existingText: subtitle.additionalText
            )
        }

        let defaultDuration = max(minDuration, 1.0)
        let upperBound = playbackDuration > anchorTime ? playbackDuration : anchorTime + defaultDuration
        let endTime = max(anchorTime + 0.2, min(anchorTime + defaultDuration, upperBound))
        return AdditionalSubtitleDraftTarget(
            subtitleID: nil,
            subtitleIndex: nil,
            playbackTime: anchorTime,
            startTime: anchorTime,
            endTime: endTime,
            existingText: ""
        )
    }

    func applyAdditionalSubtitleDraft(
        _ target: AdditionalSubtitleDraftTarget,
        text: String
    ) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let subtitleID = target.subtitleID,
           let index = subtitles.firstIndex(where: { $0.id == subtitleID }) {
            subtitles[index].additionalText = normalizedText
            subtitles = normalizedSubtitles(from: subtitles)
            selectedSubtitleID = subtitleID
            statusMessage = normalizedText.isEmpty ? "追加字幕を削除しました。" : "追加字幕を更新しました。"
        } else {
            guard !normalizedText.isEmpty else {
                present(message: "追加字幕を入力してください。")
                return
            }

            let newSubtitle = SubtitleItem(
                index: subtitles.count + 1,
                startTime: target.startTime,
                endTime: max(target.endTime, target.startTime + 0.2),
                text: "",
                additionalText: normalizedText
            )

            subtitles.append(newSubtitle)
            subtitles = normalizedSubtitles(from: subtitles)
            selectedSubtitleID = subtitles.first(where: { $0.id == newSubtitle.id })?.id ?? subtitles.last?.id
            statusMessage = "追加字幕を作成しました。"
        }

        if player?.timeControlStatus != .playing {
            seekPlayback(to: target.startTime, pauseAfterSeek: true)
        }
    }

    func translateAdditionalSubtitleText(_ text: String) async throws -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return ""
        }

        let backend = backend
        let preferences = translationPreferences
        return try await Task.detached(priority: .userInitiated) {
            try backend.translateText(normalized, preferences: preferences)
        }.value
    }

    func subtitleRegionDidChange(_ region: NormalizedRect) {
        subtitleRegion = region.clamped()
    }

    private var effectiveWrapWidthRatio: Double {
        effectiveSubtitleLayoutRect.width
    }

    private var previewSubtitleRenderSize: CGSize {
        let canvasSize = subtitleRenderCanvasSize
        let region = effectiveSubtitleLayoutRect
        return CGSize(
            width: max(40.0, canvasSize.width * region.width),
            height: max(18.0, canvasSize.height * region.height)
        )
    }

    private var additionalSubtitleRenderSize: CGSize {
        let canvasSize = subtitleRenderCanvasSize
        let region = additionalSubtitleRect
        return CGSize(
            width: max(80.0, canvasSize.width * region.width),
            height: max(28.0, canvasSize.height * region.height)
        )
    }

    private var subtitleRenderCanvasSize: CGSize {
        if let overlayImage = overlayProcessedImage ?? overlayOriginalImage {
            return overlayImage.size
        }
        if let metadata = videoMetadata, metadata.width > 0, metadata.height > 0 {
            return CGSize(width: metadata.width, height: metadata.height)
        }
        if let previewImage {
            return previewImage.size
        }
        return CGSize(width: 1920, height: 1080)
    }

    private var processingPreferences: ProcessingPreferences {
        ProcessingPreferences(
            fpsSample: fpsSample,
            detectScroll: detectScroll,
            minDuration: minDuration,
            maxDuration: maxDuration,
            wrapWidthRatio: effectiveWrapWidthRatio,
            subtitleFontSize: subtitleFontSize,
            subtitleFontName: subtitleFontName,
            subtitleOutlineWidth: subtitleOutlineWidth
        )
    }

    private var translationPreferences: TranslationPreferences {
        TranslationPreferences(
            model: translationModel,
            customDictionary: dictionaryEntries.compactMap(\.serialized).joined(separator: "\n"),
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
    }

    private var currentVideoMetadata: VideoMetadata {
        if let videoMetadata {
            return videoMetadata
        }
        return VideoMetadata(
            path: videoURL?.path ?? "",
            width: 1920,
            height: 1080,
            fps: 30.0,
            duration: subtitles.last?.endTime ?? 0.0
        )
    }

    private func normalizedSubtitles(
        from subtitles: [SubtitleItem],
        duration: Double? = nil
    ) -> [SubtitleItem] {
        SubtitleUtilities.normalizeSubtitles(
            subtitles,
            minDuration: minDuration,
            maxDuration: maxDuration,
            timelineEnd: duration ?? videoMetadata?.duration
        )
    }

    private func defaultExportFilename(for format: ExportFormat) -> String {
        let baseName: String
        if let videoURL {
            baseName = videoURL.deletingPathExtension().lastPathComponent
        } else {
            baseName = "subtitles"
        }
        let suffix = exportTextMode == .translated ? "_translated" : "_original"
        return "\(baseName)\(suffix).\(format.suggestedFilenameExtension)"
    }

    private func loadVideo(from url: URL) async {
        setBusy(true, message: "動画を読み込んでいます…")
        defer { isBusy = false }

        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try await VideoLoader.load(url: url)
            }.value

            videoURL = url
            videoMetadata = loaded.metadata
            previewImage = loaded.previewTIFFData.flatMap(NSImage.init(data:))
            configurePlayer(AVPlayer(url: url))
            subtitles = []
            selectedSubtitleID = nil
            extractionProgress = nil
            playbackTime = 0.0
            playbackScrubTime = 0.0
            isScrubbingPlayback = false
            statusMessage = "動画を開きました。字幕範囲を調整して抽出してください。"
        } catch {
            present(error: error)
        }
    }

    private func configurePlayer(_ newPlayer: AVPlayer?) {
        removePlayerTimeObserver()
        player = newPlayer

        guard let newPlayer else {
            playbackTime = 0.0
            playbackScrubTime = 0.0
            isScrubbingPlayback = false
            return
        }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        playerTimeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds.isFinite ? max(0.0, time.seconds) : 0.0
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                if !self.isScrubbingPlayback {
                    self.playbackTime = seconds
                    self.playbackScrubTime = seconds
                }
            }
        }
    }

    private func removePlayerTimeObserver() {
        if let playerTimeObserver, let player {
            player.removeTimeObserver(playerTimeObserver)
        }
        playerTimeObserver = nil
    }

    private func clampedPlaybackTime(_ seconds: Double) -> Double {
        let upperBound = playbackDuration > 0 ? playbackDuration : max(seconds, 0.0)
        return min(max(seconds, 0.0), upperBound)
    }

    private func refreshOverlayProcessingIfNeeded() {
        guard overlayOriginalImage != nil else {
            return
        }
        refreshOverlayProcessing(forceUpdateWindow: false)
    }

    private func refreshOverlayProcessing(forceUpdateWindow: Bool) {
        guard let overlayOriginalImage else {
            return
        }

        let image = overlayOriginalImage
        let keyColor = overlayKeyColor
        let tolerance = overlayTolerance
        let softness = overlaySoftness

        overlayProcessingTask?.cancel()
        overlayProcessingTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                SubtitleUtilities.processOverlayImage(
                    image,
                    keyColor: keyColor,
                    tolerance: tolerance,
                    softness: softness
                )
            }.value

            guard let self, !Task.isCancelled else {
                return
            }

            self.overlayProcessedImage = result.processedTIFFData.flatMap(NSImage.init(data:))
            if forceUpdateWindow || (!self.overlayVideoRectIsManual || self.overlayVideoRect.width <= 0.05) {
                self.overlayVideoRect = result.transparentRect ?? self.overlayVideoRect
            }
        }
    }

    private func updateExtractionProgress(_ progress: ExtractionProgress) {
        extractionProgress = progress
        statusMessage = extractionProgressText
    }

    private func setBusy(_ value: Bool, message: String) {
        isBusy = value
        statusMessage = message
    }

    private func present(error: Error) {
        errorMessage = error.localizedDescription
        isBusy = false
        extractionProgress = nil
    }

    private func present(message: String) {
        errorMessage = message
        isBusy = false
        extractionProgress = nil
    }

    private func loadOverlay(
        from url: URL,
        storedSettings: OverlayPreset? = nil,
        useCurrentSettings: Bool = false,
        announceStatus: Bool
    ) {
        guard let image = NSImage(contentsOf: url) else {
            present(message: "オーバーレイ画像を読み込めませんでした。")
            return
        }

        currentOverlayURL = url
        overlayOriginalImage = image
        overlayFileName = url.lastPathComponent
        overlayEditMode = .videoPosition

        if let storedSettings {
            overlayKeyColor = storedSettings.keyColor
            overlayTolerance = storedSettings.tolerance
            overlaySoftness = storedSettings.softness
            overlayVideoRect = storedSettings.videoRect
            overlayVideoOffset = storedSettings.videoOffset.cgSize
            overlayVideoZoom = storedSettings.videoZoom
            subtitleLayoutRect = storedSettings.subtitleRect
            additionalSubtitleLayoutRect = storedSettings.additionalSubtitleRect.clamped()
            overlayVideoRectIsManual = true
            refreshOverlayProcessing(forceUpdateWindow: false)
        } else if useCurrentSettings {
            overlayVideoRectIsManual = true
            refreshOverlayProcessing(forceUpdateWindow: false)
        } else {
            overlayVideoOffset = .zero
            overlayVideoZoom = 1.0
            overlayVideoRect = NormalizedRect(x: 0.08, y: 0.08, width: 0.84, height: 0.72)
            overlayVideoRectIsManual = false

            if let detectedColor = SubtitleUtilities.detectChromaKeyColor(in: image) {
                overlayKeyColor = detectedColor
            } else {
                refreshOverlayProcessing(forceUpdateWindow: true)
            }
        }

        if announceStatus {
            statusMessage = "オーバーレイを読み込みました。"
        }
    }

    private func setupPersistence() {
        let persistencePublishers: [AnyPublisher<Void, Never>] = [
            $fpsSample.map { _ in () }.eraseToAnyPublisher(),
            $detectScroll.map { _ in () }.eraseToAnyPublisher(),
            $minDuration.map { _ in () }.eraseToAnyPublisher(),
            $maxDuration.map { _ in () }.eraseToAnyPublisher(),
            $wrapWidthRatio.map { _ in () }.eraseToAnyPublisher(),
            $subtitleFontSize.map { _ in () }.eraseToAnyPublisher(),
            $subtitleFontName.map { _ in () }.eraseToAnyPublisher(),
            $subtitleOutlineWidth.map { _ in () }.eraseToAnyPublisher(),
            $exportTextMode.map { _ in () }.eraseToAnyPublisher(),
            $translationModel.map { _ in () }.eraseToAnyPublisher(),
            $sourceLanguage.map { _ in () }.eraseToAnyPublisher(),
            $targetLanguage.map { _ in () }.eraseToAnyPublisher(),
            $dictionaryEntries.map { _ in () }.eraseToAnyPublisher(),
            $subtitleRegion.map { _ in () }.eraseToAnyPublisher(),
            $overlayKeyColor.map { _ in () }.eraseToAnyPublisher(),
            $overlayTolerance.map { _ in () }.eraseToAnyPublisher(),
            $overlaySoftness.map { _ in () }.eraseToAnyPublisher(),
            $overlayVideoRect.map { _ in () }.eraseToAnyPublisher(),
            $overlayVideoOffset.map { _ in () }.eraseToAnyPublisher(),
            $overlayVideoZoom.map { _ in () }.eraseToAnyPublisher(),
            $subtitleLayoutRect.map { _ in () }.eraseToAnyPublisher(),
            $additionalSubtitleLayoutRect.map { _ in () }.eraseToAnyPublisher(),
            $overlayEditMode.map { _ in () }.eraseToAnyPublisher(),
            $favoriteFontNames.map { _ in () }.eraseToAnyPublisher(),
            $overlayPresets.map { _ in () }.eraseToAnyPublisher(),
            $importedFontFiles.map { _ in () }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(persistencePublishers)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.persistStateIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func persistStateIfNeeded() {
        guard !suppressPersistence else {
            return
        }

        do {
            let encoded = try JSONEncoder().encode(makePersistentState())
            UserDefaults.standard.set(encoded, forKey: persistentStateDefaultsKey)
        } catch {
            statusMessage = "設定の保存に失敗しました。"
        }
    }

    private func makePersistentState() -> PersistentAppState {
        var state = PersistentAppState()
        state.fpsSample = fpsSample
        state.detectScroll = detectScroll
        state.minDuration = minDuration
        state.maxDuration = maxDuration
        state.wrapWidthRatio = wrapWidthRatio
        state.subtitleFontSize = subtitleFontSize
        state.subtitleFontName = subtitleFontName
        state.subtitleOutlineWidth = subtitleOutlineWidth
        state.exportTextMode = exportTextMode
        state.translationModel = translationModel
        state.sourceLanguage = sourceLanguage
        state.targetLanguage = targetLanguage
        state.dictionaryEntries = dictionaryEntries
        state.subtitleRegion = subtitleRegion
        state.overlayKeyColor = overlayKeyColor
        state.overlayTolerance = overlayTolerance
        state.overlaySoftness = overlaySoftness
        state.overlayVideoRect = overlayVideoRect
        state.overlayVideoOffset = SavedSize(overlayVideoOffset)
        state.overlayVideoZoom = overlayVideoZoom
        state.subtitleLayoutRect = subtitleLayoutRect
        state.additionalSubtitleLayoutRect = additionalSubtitleLayoutRect
        state.overlayEditMode = overlayEditMode
        state.favoriteFontNames = favoriteFontNames
        state.overlayPresets = overlayPresets
        state.currentOverlayPath = currentOverlayURL?.path
        return state
    }

    private func restorePersistentState() {
        guard let data = UserDefaults.standard.data(forKey: persistentStateDefaultsKey),
              let state = try? JSONDecoder().decode(PersistentAppState.self, from: data) else {
            return
        }

        fpsSample = state.fpsSample
        detectScroll = state.detectScroll
        minDuration = state.minDuration
        maxDuration = state.maxDuration
        wrapWidthRatio = state.wrapWidthRatio
        subtitleFontSize = state.subtitleFontSize
        subtitleFontName = state.subtitleFontName
        subtitleOutlineWidth = state.subtitleOutlineWidth
        exportTextMode = state.exportTextMode
        translationModel = state.translationModel
        sourceLanguage = state.sourceLanguage
        targetLanguage = state.targetLanguage
        dictionaryEntries = state.dictionaryEntries
        subtitleRegion = state.subtitleRegion.clamped()
        overlayKeyColor = state.overlayKeyColor
        overlayTolerance = state.overlayTolerance
        overlaySoftness = state.overlaySoftness
        overlayVideoRect = state.overlayVideoRect.clamped()
        overlayVideoOffset = state.overlayVideoOffset.cgSize
        overlayVideoZoom = state.overlayVideoZoom
        subtitleLayoutRect = state.subtitleLayoutRect.clamped()
        additionalSubtitleLayoutRect = state.additionalSubtitleLayoutRect.clamped()
        overlayEditMode = state.overlayEditMode
        favoriteFontNames = Array(Set(state.favoriteFontNames.filter { !$0.isEmpty })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        overlayPresets = state.overlayPresets.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        if availableFontNames.contains(subtitleFontName) == false {
            refreshAvailableFonts(preferredSelection: subtitleFontName)
        }

        if let currentOverlayPath = state.currentOverlayPath {
            let url = URL(fileURLWithPath: currentOverlayPath)
            if FileManager.default.fileExists(atPath: url.path) {
                loadOverlay(
                    from: url,
                    useCurrentSettings: true,
                    announceStatus: false
                )
            }
        }
    }

    private func registerFontFiles(_ urls: [URL]) -> ([URL], [String]) {
        var loadedURLs: [URL] = []
        var failedFiles: [String] = []

        for url in urls {
            var registrationError: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError)
            if registered {
                loadedURLs.append(url)
                continue
            }

            let errorDescription = (registrationError?.takeRetainedValue() as Error?)?.localizedDescription ?? ""
            if errorDescription.localizedCaseInsensitiveContains("already registered") {
                loadedURLs.append(url)
            } else {
                failedFiles.append(url.lastPathComponent)
            }
        }

        return (loadedURLs, failedFiles)
    }

    private func restoreImportedFonts() {
        let storedPaths = UserDefaults.standard.stringArray(forKey: importedFontsDefaultsKey) ?? []
        let urls = storedPaths.map(URL.init(fileURLWithPath:)).filter { FileManager.default.fileExists(atPath: $0.path) }
        let (loadedURLs, _) = registerFontFiles(urls)
        importedFontFiles = Array(Set(loadedURLs)).sorted { $0.lastPathComponent < $1.lastPathComponent }
        persistImportedFonts()
    }

    private func persistImportedFonts() {
        UserDefaults.standard.set(importedFontFiles.map(\.path), forKey: importedFontsDefaultsKey)
    }

    private func refreshAvailableFonts(preferredSelection: String?) {
        let fonts = SubtitleUtilities.availableFontNames()
        availableFontNames = fonts

        if let preferredSelection, fonts.contains(preferredSelection) {
            subtitleFontName = preferredSelection
            return
        }

        if fonts.contains(subtitleFontName) {
            return
        }

        subtitleFontName =
            fonts.first(where: { $0.localizedCaseInsensitiveContains("Hiragino Sans") }) ??
            fonts.first(where: { $0.localizedCaseInsensitiveContains("Hiragino") }) ??
            fonts.first(where: { $0.localizedCaseInsensitiveContains("YuGothic") }) ??
            fonts.first ??
            "Hiragino Sans"
    }
}
