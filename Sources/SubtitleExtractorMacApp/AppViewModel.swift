import AVKit
import AppKit
import Combine
import CoreText
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    private struct PreviewRenderCache {
        let key: String
        let layout: FittedSubtitleLayout
        let image: NSImage?
    }

    @Published var player: AVPlayer?
    @Published var videoURL: URL?
    @Published var videoMetadata: VideoMetadata?
    @Published var previewImage: NSImage?
    @Published var extractionRegionPreviewImage: NSImage?
    @Published var subtitleRegion: NormalizedRect = .defaultSubtitleArea
    @Published var subtitles: [SubtitleItem] = [] {
        didSet {
            sanitizeSubtitleSelection()
        }
    }
    @Published var selectedSubtitleID: SubtitleItem.ID? {
        didSet {
            synchronizeSelectionFromPrimarySelection()
        }
    }
    @Published var selectedSubtitleIDs: Set<SubtitleItem.ID> = [] {
        didSet {
            synchronizePrimarySelectionFromSelectionSet()
        }
    }
    @Published var isBusy = false
    @Published var statusMessage = "動画を開いて、字幕範囲をドラッグで指定してください。"
    @Published var backendSummary = "Python 環境を確認中…"
    @Published var errorMessage: String?
    @Published var appLanguage: AppLanguage = .japanese {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: AppLanguage.defaultsKey)
        }
    }
    @Published var workspaceLayoutPreset: WorkspaceLayoutPreset = .balanced

    @Published var fpsSample: Double = 2.0
    @Published var ocrRefinementMode: OCRRefinementMode = .smart
    @Published var detectScroll = true
    @Published var minDuration: Double = 0.5
    @Published var maxDuration: Double = 10.0
    @Published var wrapWidthRatio: Double = 0.68
    @Published var wrapTimingMode: WrapTimingMode = .balanced
    @Published var preferredLineCount: Int = 0
    @Published var subtitleFontSize: Double = 24.0
    @Published var subtitleFontName: String
    @Published var subtitleOutlineWidth: Double = 4.0

    @Published var exportFormat: ExportFormat = .srt
    @Published var exportTextMode: ExportTextMode = .translated

    @Published var translationModel = "gemma3:4b"
    @Published var preferredVisionModel = ""
    @Published var sourceLanguage = "ja"
    @Published var targetLanguage = "en"
    @Published var useContextualTranslation = true
    @Published var translationContextWindow: Int = 2
    @Published var preserveSlangAndTone = true
    @Published var sharePreReleaseAnalytics = false
    @Published var includeDiagnosticsInFeedback = true
    @Published var availableTranslationModels: [String] = []
    @Published var isOllamaAvailable = false
    @Published var translationRuntimeSummary = "Ollama モデルを確認中…"
    @Published var isInstallingOllamaModel = false
    @Published var ollamaInstallSummary = ""
    @Published var installingOllamaModelName: String?
    @Published var translationProgress: TranslationProgress?
    @Published var useDictionaryForCurrentProject = true
    @Published var dictionaryEntries: [DictionaryEntry] = []
    @Published var extractionProgress: ExtractionProgress?
    @Published var exportProgress: ExportProgress?
    @Published var captionStylePreset: CaptionStylePreset = .classic
    @Published var ollamaExecutablePath: String?
    @Published var isRunningSetupDiagnostic = false
    @Published var setupDiagnosticSummary = "未確認"

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
    @Published var currentProjectURL: URL?
    @Published var hasUnsavedProjectChanges = false
    @Published var didRestoreAutosaveSession = false
    @Published var availableUpdate: AppUpdateInfo?
    @Published var isCheckingForUpdates = false
    @Published var automaticallyChecksForUpdates = true
    @Published var automaticallyDownloadsUpdates = false
    @Published var includePrereleaseUpdates = false
    @Published var updateCheckInterval: UpdateCheckInterval = .daily
    @Published var lastUpdateCheckAt: Date?
    @Published var isDownloadingUpdate = false
    @Published var updateDownloadProgress = 0.0
    @Published var downloadedUpdateFileURL: URL?
    @Published var downloadedUpdateVersion: String?
    @Published var updateRuntimeSummary = "更新確認待ち"
    @Published private(set) var feedbackLogEntries: [FeedbackLogEntry] = []

    private let backend = PythonBackendBridge()
    private var overlayProcessingTask: Task<Void, Never>?
    private var overlayVideoRectIsManual = false
    private let importedFontsDefaultsKey = "CaptionStudio.importedFonts"
    private let persistentStateDefaultsKey = "CaptionStudio.persistentState"
    private var currentOverlayURL: URL?
    private var cancellables = Set<AnyCancellable>()
    private var suppressPersistence = true
    private var playerTimeObserver: Any?
    private var extractionRegionPreviewTask: Task<Void, Never>?
    private var extractionRegionPreviewKey: String?
    private var previewSubtitleRenderCache: PreviewRenderCache?
    private var previewAdditionalSubtitleRenderCache: PreviewRenderCache?
    private var didAttemptAutosaveRestore = false
    private var systemCaptionAppearance: SystemCaptionAppearance?
    private var dismissedUpdateVersion: String?
    private var hasPreparedAutomaticUpdateChecks = false
    private var isSynchronizingSubtitleSelection = false

    weak var undoManager: UndoManager?

    init() {
        _subtitleFontName = Published(
            initialValue: "Hiragino Sans"
        )
        appLanguage = AppLanguage(storedRawValue: UserDefaults.standard.string(forKey: AppLanguage.defaultsKey))
        restorePersistentState()
        refreshAvailableFonts(preferredSelection: subtitleFontName)
        setupPersistence()
        suppressPersistence = false
        refreshSystemCaptionAppearance()
        refreshRuntimeStatus()
        refreshUpdateRuntimeSummary()
    }

    var selectedSubtitle: SubtitleItem? {
        guard let selectedSubtitleID else {
            return nil
        }
        return subtitles.first(where: { $0.id == selectedSubtitleID })
    }

    var selectedSubtitles: [SubtitleItem] {
        subtitles.filter { selectedSubtitleIDs.contains($0.id) }
    }

    var hasMultipleSubtitleSelection: Bool {
        selectedSubtitleIDs.count > 1
    }

    var hasAnySubtitleSelection: Bool {
        !selectedSubtitleIDs.isEmpty
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

    var projectDisplayName: String {
        currentProjectURL?.deletingPathExtension().lastPathComponent ?? "未保存プロジェクト"
    }

    var currentVersionString: String {
        UpdateChecker.currentVersion()
    }

    var updateLastCheckedText: String {
        guard let lastUpdateCheckAt else {
            return localized(
                "まだ確認していません",
                "Not checked yet",
                "尚未检查",
                "아직 확인하지 않음"
            )
        }

        return lastUpdateCheckAt.formatted(date: .abbreviated, time: .shortened)
    }

    var updateDownloadDetailText: String {
        if isDownloadingUpdate {
            let percent = Int((updateDownloadProgress * 100.0).rounded())
            return localized(
                "アップデートをダウンロード中… \(percent)%",
                "Downloading update… \(percent)%",
                "正在下载更新… \(percent)%",
                "업데이트 다운로드 중… \(percent)%"
            )
        }

        if let downloadedUpdateVersion, let downloadedUpdateFileURL {
            return localized(
                "バージョン \(downloadedUpdateVersion) のインストーラーを保存済みです。\(downloadedUpdateFileURL.lastPathComponent)",
                "Installer for version \(downloadedUpdateVersion) is ready. \(downloadedUpdateFileURL.lastPathComponent)",
                "版本 \(downloadedUpdateVersion) 的安装包已准备好。\(downloadedUpdateFileURL.lastPathComponent)",
                "버전 \(downloadedUpdateVersion) 설치 파일이 준비되었습니다. \(downloadedUpdateFileURL.lastPathComponent)"
            )
        }

        if let update = availableUpdate {
            return localized(
                "バージョン \(update.version) をダウンロードできます。",
                "Version \(update.version) is ready to download.",
                "可以下载版本 \(update.version)。",
                "버전 \(update.version) 을 다운로드할 수 있습니다."
            )
        }

        return localized(
            "更新が見つかるとここにダウンロード状況を表示します。",
            "Download status will appear here when an update is available.",
            "检测到更新后，这里会显示下载状态。",
            "업데이트가 있으면 여기에 다운로드 상태를 표시합니다."
        )
    }

    var hasDownloadedUpdateReady: Bool {
        guard let downloadedUpdateVersion, let downloadedUpdateFileURL else {
            return false
        }
        guard FileManager.default.fileExists(atPath: downloadedUpdateFileURL.path) else {
            return false
        }
        if let availableUpdate {
            return availableUpdate.version == downloadedUpdateVersion
        }
        return UpdateChecker.compareVersions(downloadedUpdateVersion, currentVersionString) == .orderedDescending
    }

    var canSaveProject: Bool {
        videoURL != nil || !subtitles.isEmpty
    }

    var previewWrappedText: String {
        resolvedPreviewSubtitleRender().layout.text
    }

    var previewSubtitleImage: NSImage? {
        resolvedPreviewSubtitleRender().image
    }

    var previewAdditionalSubtitleImage: NSImage? {
        resolvedPreviewAdditionalSubtitleRender().image
    }

    var previewSubtitleLayout: FittedSubtitleLayout {
        resolvedPreviewSubtitleRender().layout
    }

    var previewAdditionalSubtitleLayout: FittedSubtitleLayout {
        resolvedPreviewAdditionalSubtitleRender().layout
    }

    var effectiveSubtitleLayoutRect: NormalizedRect {
        if hasOverlay {
            return subtitleLayoutRect
        }
        return SubtitleUtilities.defaultSubtitleLayoutRect(
            for: currentVideoCanvasSize,
            wrapWidthRatio: wrapWidthRatio
        )
    }

    var extractionProgressValue: Double {
        extractionProgress?.fractionCompleted ?? 0.0
    }

    var translationProgressValue: Double {
        translationProgress?.fractionCompleted ?? 0.0
    }

    var exportProgressValue: Double {
        exportProgress?.clampedFractionCompleted ?? 0.0
    }

    var translationProgressText: String {
        guard let translationProgress else {
            return localized("翻訳待機中", "Translation idle", "翻译待机中", "번역 대기 중")
        }
        return localized(
            "字幕を翻訳中: \(translationProgress.processed) / \(translationProgress.total)",
            "Translating subtitles: \(translationProgress.processed) / \(translationProgress.total)",
            "正在翻译字幕：\(translationProgress.processed) / \(translationProgress.total)",
            "자막 번역 중: \(translationProgress.processed) / \(translationProgress.total)"
        )
    }

    var translationProgressDetail: String {
        guard let translationProgress else {
            return localized(
                "Ollama で字幕を翻訳します。",
                "Translate subtitles with Ollama.",
                "使用 Ollama 翻译字幕。",
                "Ollama로 자막을 번역합니다."
            )
        }
        let text = translationProgress.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return "翻訳対象の字幕を処理しています。"
        }
        return text
    }

    var exportProgressText: String {
        guard let exportProgress else {
            return localized("書き出し待機中", "Export idle", "导出待机中", "내보내기 대기 중")
        }

        let percent = Int((exportProgress.clampedFractionCompleted * 100.0).rounded())
        return localized(
            "\(exportProgress.format.displayName) を書き出し中: \(percent)%",
            "Exporting \(exportProgress.format.displayName): \(percent)%",
            "正在导出 \(exportProgress.format.displayName)：\(percent)%",
            "\(exportProgress.format.displayName) 내보내는 중: \(percent)%"
        )
    }

    var exportProgressDetail: String {
        guard let exportProgress else {
            return localized(
                "MP4 / MOV の字幕焼き込みを書き出します。",
                "Burning subtitles into MP4 / MOV.",
                "正在烧录 MP4 / MOV 字幕。",
                "MP4 / MOV 자막을 입혀서 내보냅니다."
            )
        }

        let remainingText: String
        if let remainingSeconds = exportProgress.estimatedRemainingSeconds, remainingSeconds.isFinite {
            remainingText = localized(
                "残り約 \(SubtitleUtilities.compactDuration(remainingSeconds))",
                "About \(SubtitleUtilities.compactDuration(remainingSeconds)) remaining",
                "预计还需 \(SubtitleUtilities.compactDuration(remainingSeconds))",
                "약 \(SubtitleUtilities.compactDuration(remainingSeconds)) 남음"
            )
        } else {
            remainingText = localized(
                "残り時間を計算中",
                "Calculating remaining time",
                "正在估算剩余时间",
                "남은 시간 계산 중"
            )
        }

        let elapsedText = localized(
            "経過 \(SubtitleUtilities.compactDuration(exportProgress.elapsedSeconds))",
            "Elapsed \(SubtitleUtilities.compactDuration(exportProgress.elapsedSeconds))",
            "已用时 \(SubtitleUtilities.compactDuration(exportProgress.elapsedSeconds))",
            "경과 \(SubtitleUtilities.compactDuration(exportProgress.elapsedSeconds))"
        )
        return "\(remainingText)  •  \(elapsedText)"
    }

    var extractionProgressText: String {
        guard let extractionProgress else {
            return localized("抽出待機中", "Extraction idle", "提取待机中", "추출 대기 중")
        }

        let current = SubtitleUtilities.compactTimestamp(extractionProgress.timestamp)
        if let duration = videoMetadata?.duration, duration > 0 {
            let end = SubtitleUtilities.compactTimestamp(duration)
            return localized(
                "字幕領域をスキャン中: \(current) / \(end)",
                "Scanning subtitle area: \(current) / \(end)",
                "正在扫描字幕区域：\(current) / \(end)",
                "자막 영역 스캔 중: \(current) / \(end)"
            )
        }
        return localized(
            "字幕領域をスキャン中: \(current)",
            "Scanning subtitle area: \(current)",
            "正在扫描字幕区域：\(current)",
            "자막 영역 스캔 중: \(current)"
        )
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

    var activeDictionarySummary: String {
        let completeCount = dictionaryEntries.filter(\.isComplete).count
        guard completeCount > 0 else {
            return localized("辞書はまだ登録されていません。", "No glossary entries yet.", "词典里还没有词条。", "사전에 아직 등록된 항목이 없습니다.")
        }
        guard useDictionaryForCurrentProject else {
            return localized("この動画では辞書を使いません。", "The glossary is disabled for this video.", "这个视频不会使用词典。", "이 영상에서는 사전을 사용하지 않습니다.")
        }

        let activeCount = activeDictionaryEntriesForCurrentTranslation.count
        return localized(
            "今回の翻訳で \(activeCount) 件を使います。",
            "Using \(activeCount) entries for this translation.",
            "本次翻译会使用 \(activeCount) 条词条。",
            "이번 번역에 \(activeCount)개 항목을 사용합니다."
        )
    }

    var translationContextSummary: String {
        guard useContextualTranslation else {
            return localized(
                "各字幕を単独で翻訳します。",
                "Each subtitle will be translated on its own.",
                "每条字幕都会单独翻译。",
                "각 자막을 단독으로 번역합니다."
            )
        }

        let toneSummary = preserveSlangAndTone
            ? localized(
                "口調とスラングも反映します。",
                "Tone and slang will be preserved.",
                "会尽量保留语气和俚语。",
                "말투와 슬랭도 반영합니다."
            )
            : localized(
                "意味を優先して整えます。",
                "The translation will favor clean meaning.",
                "会优先保持意思清晰。",
                "의미 전달을 우선합니다."
            )

        return localized(
            "前後 \(translationContextWindow) 件の流れを見ながら訳します。\(toneSummary)",
            "Uses \(translationContextWindow) lines of context on each side. \(toneSummary)",
            "会参考前后各 \(translationContextWindow) 条字幕。\(toneSummary)",
            "앞뒤 \(translationContextWindow)줄 문맥을 함께 봅니다. \(toneSummary)"
        )
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
        !subtitles.isEmpty && !isBusy && !translationModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var ollamaUnavailableMessage: String {
        localized(
            "Ollama に接続できません。Ollama アプリを起動するか、ターミナルで `ollama serve` を実行してから再試行してください。",
            "Can't connect to Ollama. Launch the Ollama app or run `ollama serve`, then try again.",
            "无法连接到 Ollama。请启动 Ollama 应用，或在终端运行 `ollama serve` 后重试。",
            "Ollama에 연결할 수 없습니다. Ollama 앱을 실행하거나 터미널에서 `ollama serve` 를 실행한 뒤 다시 시도하세요."
        )
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

    var selectedSourceTranslationLanguage: TranslationLanguage {
        get { TranslationLanguage(rawValue: sourceLanguage) ?? .japanese }
        set { sourceLanguage = newValue.rawValue }
    }

    var selectedTargetTranslationLanguage: TranslationLanguage {
        get { TranslationLanguage(rawValue: targetLanguage) ?? .english }
        set { targetLanguage = newValue.rawValue }
    }

    var isOllamaInstalled: Bool {
        ollamaExecutablePath != nil
    }

    var recommendedOllamaModels: [OllamaModelRecommendation] {
        let source = selectedSourceTranslationLanguage
        let target = selectedTargetTranslationLanguage

        if source == .korean || target == .korean {
            return [
                OllamaModelRecommendation(modelName: "exaone3.5:7.8b", purpose: .translation, focusLanguage: .korean),
                OllamaModelRecommendation(modelName: "translategemma", purpose: .translation, focusLanguage: .korean),
                OllamaModelRecommendation(modelName: "qwen2.5vl", purpose: .visionOCR, focusLanguage: .korean),
            ]
        }

        if source == .chinese || target == .chinese {
            return [
                OllamaModelRecommendation(modelName: "qwen2.5", purpose: .translation, focusLanguage: .chinese),
                OllamaModelRecommendation(modelName: "translategemma", purpose: .translation, focusLanguage: .chinese),
                OllamaModelRecommendation(modelName: "qwen2.5vl", purpose: .visionOCR, focusLanguage: .chinese),
            ]
        }

        if source == .english || target == .english {
            return [
                OllamaModelRecommendation(modelName: "translategemma", purpose: .translation, focusLanguage: .english),
                OllamaModelRecommendation(modelName: "gemma3:4b", purpose: .translation, focusLanguage: .english),
                OllamaModelRecommendation(modelName: "qwen2.5vl", purpose: .visionOCR, focusLanguage: .english),
            ]
        }

        return [
            OllamaModelRecommendation(modelName: "translategemma", purpose: .translation, focusLanguage: .japanese),
            OllamaModelRecommendation(modelName: "gemma3:4b", purpose: .translation, focusLanguage: .japanese),
            OllamaModelRecommendation(modelName: "qwen2.5vl", purpose: .visionOCR, focusLanguage: .japanese),
        ]
    }

    var effectiveSubtitleFontName: String {
        if let preferred = CaptionStyleResolver.preferredFontName(
            for: captionStylePreset,
            systemAppearance: systemCaptionAppearance
        ) {
            return preferred
        }
        return subtitleFontName
    }

    var effectiveCaptionVisualStyle: CaptionVisualStyle {
        CaptionStyleResolver.visualStyle(
            for: captionStylePreset,
            systemAppearance: systemCaptionAppearance
        )
    }

    var automaticOCRSummary: String {
        let baseSummary: String
        switch selectedSourceTranslationLanguage {
        case .japanese:
            baseSummary = localized(
                "字幕言語が日本語のため、日本語向けの抽出モードを自動で使います。",
                "Japanese subtitle mode is selected automatically for Japanese extraction.",
                "当前字幕语言为日语，将自动使用日语优化的提取模式。",
                "자막 언어가 일본어이므로 일본어에 맞춘 추출 모드를 자동으로 사용합니다."
            )
        case .english:
            baseSummary = localized(
                "字幕言語が英語のため、macOS 標準の多言語 OCR を自動で使います。",
                "English subtitles use the macOS multilingual OCR mode automatically.",
                "当前字幕语言为英语，将自动使用 macOS 标准多语言 OCR。",
                "자막 언어가 영어이므로 macOS 기본 다국어 OCR을 자동으로 사용합니다."
            )
        case .chinese:
            baseSummary = localized(
                "字幕言語が中国語のため、macOS 標準 OCR を使います。",
                "Chinese subtitles use macOS OCR automatically.",
                "当前字幕语言为中文，将自动使用 macOS OCR。",
                "자막 언어가 중국어이므로 macOS OCR을 자동으로 사용합니다."
            )
        case .korean:
            baseSummary = localized(
                "字幕言語が韓国語のため、macOS 標準 OCR を使います。",
                "Korean subtitles use macOS OCR automatically.",
                "当前字幕语言为韩语，将自动使用 macOS OCR。",
                "자막 언어가 한국어이므로 macOS OCR을 자동으로 사용합니다."
            )
        }

        return "\(baseSummary) \(ocrRefinementMode.shortDescription(in: appLanguage))"
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

    func makeFeedbackDraft(prefillMessage: String? = nil) -> FeedbackDraft {
        FeedbackDraft(
            category: .bug,
            message: prefillMessage ?? "",
            includeScreenshot: true,
            includeDiagnostics: includeDiagnosticsInFeedback
        )
    }

    func submitFeedback(_ draft: FeedbackDraft) throws -> FeedbackSubmissionResult {
        let context = FeedbackReportContext(
            appVersion: UpdateChecker.currentVersion(),
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-",
            appLanguage: appLanguage.rawValue,
            subtitleLanguage: sourceLanguage,
            translationTargetLanguage: targetLanguage,
            translationModel: translationModel,
            preferredVisionModel: preferredVisionModel,
            ollamaAvailable: isOllamaAvailable,
            currentVideoName: videoURL?.lastPathComponent,
            currentProjectName: currentProjectURL?.lastPathComponent,
            latestStatusMessage: statusMessage,
            latestErrorMessage: errorMessage,
            sharePreReleaseAnalytics: sharePreReleaseAnalytics,
            includeDiagnosticsInFeedback: includeDiagnosticsInFeedback,
            workspaceLayout: workspaceLayoutPreset.rawValue,
            timestamp: Date(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            recentLogs: feedbackLogEntries
        )

        let archiveURL = try FeedbackService.createArchive(
            context: context,
            draft: draft,
            window: NSApp.keyWindow ?? NSApp.mainWindow
        )
        let opened = FeedbackService.composeEmail(draft: draft, archiveURL: archiveURL)
        recordFeedbackLog(
            opened
                ? "フィードバック送信を開始しました。"
                : "フィードバック添付ファイルを作成しました。",
            level: .info
        )
        return FeedbackSubmissionResult(archiveURL: archiveURL, mailComposerOpened: opened)
    }

    func configureUndoManager(_ undoManager: UndoManager?) {
        self.undoManager = undoManager
    }

    func restoreAutosavedProjectIfNeeded() {
        guard !didAttemptAutosaveRestore else {
            return
        }
        didAttemptAutosaveRestore = true

        Task {
            do {
                guard let autosave = try ProjectStore.loadAutosave(),
                      autosave.videoPath != nil || !autosave.subtitles.isEmpty else {
                    return
                }
                await applyProjectDocument(
                    autosave,
                    projectURL: nil,
                    restoredFromAutosave: true,
                    announceStatus: "前回の作業を復元しました。"
                )
                didRestoreAutosaveSession = true
            } catch {
                statusMessage = "自動保存の復元に失敗しました。"
            }
        }
    }

    func newProject() {
        clearWorkspace()
        currentProjectURL = nil
        hasUnsavedProjectChanges = false
        didRestoreAutosaveSession = false
        try? ProjectStore.clearAutosave()
        statusMessage = "新規プロジェクトを開始しました。"
    }

    func openPrimaryPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .subtitleProject,
            .json,
            .movie,
            .mpeg4Movie,
            .quickTimeMovie,
            UTType(filenameExtension: "srt") ?? .plainText,
        ]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = localized(
            "プロジェクト・動画・SRT を開く",
            "Open Project, Video, or SRT",
            "打开项目、视频或 SRT",
            "프로젝트, 동영상 또는 SRT 열기"
        )

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        openFile(url)
    }

    func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.subtitleProject, .json]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "プロジェクトを開く"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        openProject(at: url)
    }

    func openFile(_ url: URL) {
        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        let fileExtension = url.pathExtension.lowercased()

        if contentType?.conforms(to: .subtitleProject) == true ||
            ProjectStore.looksLikeProjectFile(at: url) {
            openProject(at: url)
            return
        }

        if fileExtension == "srt" {
            importSRT(from: url)
            return
        }

        if contentType?.conforms(to: .movie) == true ||
            contentType?.conforms(to: .mpeg4Movie) == true ||
            contentType?.conforms(to: .quickTimeMovie) == true ||
            ["mp4", "mov", "m4v", "webm"].contains(fileExtension) {
            Task {
                await loadVideo(from: url)
            }
            return
        }

        present(
            message: localized(
                "このファイルはプロジェクト、動画、SRT として開けませんでした。",
                "This file couldn't be opened as a project, video, or SRT.",
                "该文件无法作为项目、视频或 SRT 打开。",
                "이 파일은 프로젝트, 동영상 또는 SRT 로 열 수 없습니다."
            )
        )
    }

    private func openProject(at url: URL) {
        Task {
            do {
                let project = try ProjectStore.load(from: url)
                await applyProjectDocument(
                    project,
                    projectURL: url,
                    restoredFromAutosave: false,
                    announceStatus: "プロジェクトを読み込みました。"
                )
            } catch {
                present(error: error)
            }
        }
    }

    func saveProjectPanel(forceChooseLocation: Bool = false) {
        guard canSaveProject else {
            present(message: "保存するプロジェクトがありません。")
            return
        }

        if !forceChooseLocation, let currentProjectURL {
            saveProject(to: currentProjectURL)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.subtitleProject]
        panel.canCreateDirectories = true
        panel.title = "プロジェクトを保存"
        panel.nameFieldStringValue = "\(projectDisplayName).\(ProductConstants.projectFileExtension)"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        saveProject(to: ProjectStore.normalizedProjectURL(for: url))
    }

    func prepareAutomaticUpdateChecks() {
        guard !hasPreparedAutomaticUpdateChecks else {
            return
        }
        hasPreparedAutomaticUpdateChecks = true

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await self?.performAutomaticUpdateCheckIfNeeded()
        }
    }

    func handleApplicationDidBecomeActive() {
        Task { @MainActor [weak self] in
            await self?.performAutomaticUpdateCheckIfNeeded()
        }
    }

    func checkForUpdates() {
        checkForUpdates(userInitiated: true)
    }

    func checkForUpdates(userInitiated: Bool) {
        guard !isCheckingForUpdates else {
            return
        }

        isCheckingForUpdates = true
        updateRuntimeSummary = userInitiated
            ? localized("更新を確認しています…", "Checking for updates…", "正在检查更新…", "업데이트 확인 중…")
            : localized("バックグラウンドで更新を確認しています…", "Checking for updates in the background…", "正在后台检查更新…", "백그라운드에서 업데이트를 확인하는 중…")

        Task { @MainActor in
            defer { isCheckingForUpdates = false }
            do {
                let update = try await UpdateChecker.checkForUpdates(
                    currentVersion: currentVersionString,
                    includePrerelease: includePrereleaseUpdates
                )
                lastUpdateCheckAt = Date()

                if let update {
                    let storedUpdateURL = UpdateInstaller.storedUpdateURL(for: update)
                    availableUpdate = userInitiated || shouldPresentUpdate(version: update.version) || storedUpdateURL != nil
                        ? update
                        : nil
                    downloadedUpdateFileURL = storedUpdateURL
                    downloadedUpdateVersion = storedUpdateURL == nil ? nil : update.version

                    if storedUpdateURL != nil {
                        updateRuntimeSummary = localized(
                            "新しいバージョン \(update.version) はダウンロード済みです。",
                            "Version \(update.version) is already downloaded.",
                            "新版本 \(update.version) 已下载完成。",
                            "새 버전 \(update.version) 이 이미 다운로드되었습니다."
                        )
                        statusMessage = localized(
                            "新しいアップデートをすぐにインストールできます。",
                            "The new update is ready to install.",
                            "新更新已准备好安装。",
                            "새 업데이트를 바로 설치할 수 있습니다."
                        )
                    } else {
                        updateRuntimeSummary = localized(
                            "新しいバージョン \(update.version) があります。",
                            "Version \(update.version) is available.",
                            "有新版本 \(update.version)。",
                            "새 버전 \(update.version) 이 있습니다."
                        )
                        statusMessage = localized(
                            "新しいアップデートを検出しました。",
                            "A new update is available.",
                            "检测到了新更新。",
                            "새 업데이트를 찾았습니다."
                        )

                        if automaticallyDownloadsUpdates {
                            try await downloadUpdate(update, openInstallerAfterDownload: false)
                        }
                    }
                } else {
                    availableUpdate = nil
                    downloadedUpdateFileURL = nil
                    downloadedUpdateVersion = nil
                    updateRuntimeSummary = localized(
                        "この Mac のアプリは最新です。",
                        "This Mac already has the latest version.",
                        "这台 Mac 上的应用已经是最新版本。",
                        "이 Mac 의 앱은 최신 버전입니다."
                    )
                    if userInitiated {
                        statusMessage = localized(
                            "最新バージョンです。",
                            "You're already up to date.",
                            "已经是最新版本。",
                            "이미 최신 버전입니다."
                        )
                    }
                }
                persistStateIfNeeded()
                refreshUpdateRuntimeSummary()
            } catch {
                updateRuntimeSummary = localized(
                    "更新確認に失敗しました。",
                    "Couldn't check for updates.",
                    "检查更新失败。",
                    "업데이트 확인에 실패했습니다."
                )
                if userInitiated {
                    present(error: error)
                } else {
                    recordFeedbackLog(error.localizedDescription, level: .warning)
                }
            }
        }
    }

    func downloadAvailableUpdate() {
        guard let availableUpdate else {
            return
        }
        Task { @MainActor in
            do {
                try await downloadUpdate(availableUpdate, openInstallerAfterDownload: false)
            } catch {
                present(error: error)
            }
        }
    }

    func installDownloadedUpdate() {
        guard hasDownloadedUpdateReady, let downloadedUpdateFileURL else {
            present(message: localized(
                "インストールできるアップデートがまだありません。",
                "There isn't a downloaded update ready to install yet.",
                "还没有可安装的已下载更新。",
                "설치할 수 있는 다운로드된 업데이트가 아직 없습니다."
            ))
            return
        }

        if UpdateInstaller.openInstaller(at: downloadedUpdateFileURL) {
            statusMessage = localized(
                "インストーラーを開きました。必要に応じて Caption Studio を終了してから更新してください。",
                "The installer is open. Quit Caption Studio if the installer asks for it.",
                "安装程序已打开。如有提示，请退出 Caption Studio 后继续更新。",
                "설치 프로그램을 열었습니다. 필요하면 Caption Studio 를 종료한 뒤 업데이트하세요."
            )
        } else {
            present(message: localized(
                "インストーラーを開けませんでした。",
                "Couldn't open the installer.",
                "无法打开安装程序。",
                "설치 프로그램을 열 수 없습니다."
            ))
        }
    }

    func dismissAvailableUpdate() {
        dismissedUpdateVersion = availableUpdate?.version
        availableUpdate = nil
        persistStateIfNeeded()
        refreshUpdateRuntimeSummary()
    }

    func addDictionaryEntry() {
        dictionaryEntries.append(
            DictionaryEntry(
                sourceLanguageScope: DictionaryLanguageScope(language: selectedSourceTranslationLanguage),
                targetLanguageScope: DictionaryLanguageScope(language: selectedTargetTranslationLanguage),
                isEnabledForCurrentVideo: true
            )
        )
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
        overlayVideoRect = SubtitleUtilities.defaultOverlayVideoRect(for: currentVideoCanvasSize)
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

    func setSelectedSubtitleIDs(
        _ ids: Set<SubtitleItem.ID>,
        primary preferredPrimaryID: SubtitleItem.ID? = nil,
        seek: Bool = false
    ) {
        let orderedIDs = orderedSubtitleIDs(from: ids)
        let validIDs = Set(orderedIDs)
        let resolvedPrimary = preferredPrimaryID.flatMap { validIDs.contains($0) ? $0 : nil }
            ?? selectedSubtitleID.flatMap { validIDs.contains($0) ? $0 : nil }
            ?? orderedIDs.first

        isSynchronizingSubtitleSelection = true
        selectedSubtitleIDs = validIDs
        selectedSubtitleID = resolvedPrimary
        isSynchronizingSubtitleSelection = false

        if seek, resolvedPrimary != nil {
            seekToSelectedSubtitle()
        }
    }

    func clearSubtitleSelection() {
        setSelectedSubtitleIDs([], primary: nil, seek: false)
    }

    func selectSubtitle(_ subtitle: SubtitleItem, additive: Bool = false, seek: Bool = true) {
        if additive {
            var ids = selectedSubtitleIDs
            if ids.contains(subtitle.id) {
                ids.remove(subtitle.id)
            } else {
                ids.insert(subtitle.id)
            }
            setSelectedSubtitleIDs(ids, primary: ids.contains(subtitle.id) ? subtitle.id : nil, seek: seek && ids.count == 1)
            return
        }

        setSelectedSubtitleIDs([subtitle.id], primary: subtitle.id, seek: seek)
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
        scheduleExtractionRegionPreviewRefresh(for: playbackScrubTime, force: true)
    }

    func updatePlaybackScrub(to seconds: Double) {
        playbackScrubTime = clampedPlaybackTime(seconds)
        scheduleExtractionRegionPreviewRefresh(for: playbackScrubTime)
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
        scheduleExtractionRegionPreviewRefresh(for: target, force: true)

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
        ollamaExecutablePath = SubtitleUtilities.executablePath(named: "ollama")
        let backend = backend
        Task {
            do {
                async let reportTask = Task.detached(priority: .utility) {
                    try backend.checkEnvironment()
                }.value
                async let modelTask = Task.detached(priority: .utility) {
                    try? backend.availableOllamaModels()
                }.value

                let report = try await reportTask
                if report.isReady {
                    if selectedSourceTranslationLanguage == .japanese,
                       report.optionalMissingModules.contains("meikiocr") {
                        backendSummary = localized(
                            "Python 環境: 利用可能 (\(report.python)) / 日本語向け追加 OCR は未導入",
                            "Python runtime ready (\(report.python)) / Japanese add-on OCR is not installed",
                            "Python 环境可用 (\(report.python)) / 日语增强 OCR 尚未安装",
                            "Python 환경 사용 가능 (\(report.python)) / 일본어 추가 OCR이 아직 설치되지 않음"
                        )
                    } else {
                        backendSummary = localized(
                            "Python 環境: 利用可能 (\(report.python))",
                            "Python runtime ready (\(report.python))",
                            "Python 环境可用 (\(report.python))",
                            "Python 환경 사용 가능 (\(report.python))"
                        )
                    }
                } else {
                    let joined = report.missingModules.joined(separator: ", ")
                    backendSummary = localized(
                        "不足モジュール: \(joined)",
                        "Missing Python modules: \(joined)",
                        "缺少 Python 模块：\(joined)",
                        "누락된 Python 모듈: \(joined)"
                    )
                }

                let modelPayload = await modelTask
                applyAvailableTranslationModels(modelPayload)
            } catch {
                backendSummary = error.localizedDescription
                isOllamaAvailable = false
                translationRuntimeSummary = localized(
                    "Ollama モデルを取得できませんでした。",
                    "Couldn't fetch Ollama models.",
                    "无法获取 Ollama 模型。",
                    "Ollama 모델을 가져오지 못했습니다."
                )
            }
        }
    }

    func refreshTranslationModels(showAlertIfUnavailable: Bool = false) {
        let backend = backend
        ollamaExecutablePath = SubtitleUtilities.executablePath(named: "ollama")
        translationRuntimeSummary = localized(
            "Ollama モデルを更新中…",
            "Refreshing Ollama models…",
            "正在刷新 Ollama 模型…",
            "Ollama 모델을 새로 고치는 중…"
        )

        Task {
            let payload = await Task.detached(priority: .utility) {
                try? backend.availableOllamaModels()
            }.value

            await MainActor.run {
                applyAvailableTranslationModels(payload)
                if showAlertIfUnavailable, isOllamaAvailable == false {
                    present(message: ollamaUnavailableMessage)
                }
            }
        }
    }

    func hasInstalledOllamaModel(_ modelName: String) -> Bool {
        resolveInstalledModelName(modelName) != nil
    }

    func resolveInstalledModelName(_ modelName: String) -> String? {
        let normalized = modelName.lowercased()
        let baseName = normalized.split(separator: ":").first.map(String.init) ?? normalized
        return availableTranslationModels.first { installed in
            let installedNormalized = installed.lowercased()
            let installedBase = installedNormalized.split(separator: ":").first.map(String.init) ?? installedNormalized
            return installedNormalized == normalized || installedBase == baseName
        }
    }

    func installRecommendedOllamaModel(_ recommendation: OllamaModelRecommendation) {
        let modelName = recommendation.modelName
        if let resolvedModel = resolveInstalledModelName(modelName) {
            applyInstalledRecommendedModel(resolvedModel, purpose: recommendation.purpose)
            return
        }

        guard let ollamaPath = ollamaExecutablePath ?? SubtitleUtilities.executablePath(named: "ollama") else {
            present(message: ollamaUnavailableMessage)
            return
        }

        ollamaExecutablePath = ollamaPath
        guard !isInstallingOllamaModel else {
            return
        }

        isInstallingOllamaModel = true
        installingOllamaModelName = modelName
        ollamaInstallSummary = localized(
            "`\(modelName)` をインストールしています…",
            "Installing `\(modelName)`…",
            "正在安装 `\(modelName)`…",
            "`\(modelName)` 설치 중…"
        )

        Task {
            do {
                try await Self.pullOllamaModel(
                    executablePath: ollamaPath,
                    modelName: modelName
                ) { [weak self] line in
                    guard let self else { return }
                    Task { @MainActor in
                        self.ollamaInstallSummary = line
                    }
                }

                await MainActor.run {
                    isInstallingOllamaModel = false
                    installingOllamaModelName = nil
                }
                refreshTranslationModels()
                let resolvedModel = resolveInstalledModelName(modelName) ?? modelName
                applyInstalledRecommendedModel(resolvedModel, purpose: recommendation.purpose)
                ollamaInstallSummary = localized(
                    "`\(modelName)` の準備ができました。",
                    "`\(modelName)` is ready.",
                    "`\(modelName)` 已准备好。",
                    "`\(modelName)` 준비가 완료되었습니다."
                )
                statusMessage = ollamaInstallSummary
            } catch {
                await MainActor.run {
                    isInstallingOllamaModel = false
                    installingOllamaModelName = nil
                }
                present(error: error)
            }
        }
    }

    private func applyInstalledRecommendedModel(_ modelName: String, purpose: OllamaModelPurpose) {
        switch purpose {
        case .translation:
            translationModel = modelName
            statusMessage = localized(
                "`\(translationModel)` を翻訳モデルに設定しました。",
                "Set `\(translationModel)` as the translation model.",
                "已将 `\(translationModel)` 设为翻译模型。",
                "`\(translationModel)` 모델을 번역용으로 설정했습니다."
            )
        case .visionOCR:
            preferredVisionModel = modelName
            statusMessage = localized(
                "`\(preferredVisionModel)` を AI 再認識モデルに設定しました。",
                "Set `\(preferredVisionModel)` as the AI rerecognition model.",
                "已将 `\(preferredVisionModel)` 设为 AI 重新识别模型。",
                "`\(preferredVisionModel)` 모델을 AI 재인식용으로 설정했습니다."
            )
        }
    }

    func refreshSystemCaptionAppearance() {
        systemCaptionAppearance = CaptionStyleResolver.loadSystemAppearance()
    }

    func applySystemCaptionPreset() {
        refreshSystemCaptionAppearance()
        captionStylePreset = .systemAccessibility
        if let preferredFontName = systemCaptionAppearance?.preferredFontName,
           !preferredFontName.isEmpty {
            subtitleFontName = preferredFontName
        }
        statusMessage = localized(
            "macOS の字幕アクセシビリティ設定を読み込みました。",
            "Loaded the macOS caption accessibility style.",
            "已载入 macOS 字幕辅助功能样式。",
            "macOS 자막 손쉬운 사용 스타일을 불러왔습니다."
        )
    }

    func runSetupDiagnostic() {
        guard !isRunningSetupDiagnostic else {
            return
        }

        isRunningSetupDiagnostic = true
        setupDiagnosticSummary = localized(
            "動作チェックを実行中…",
            "Running checks…",
            "正在运行检查…",
            "동작 확인을 실행 중…"
        )

        Task {
            defer { isRunningSetupDiagnostic = false }
            refreshRuntimeStatus()

            do {
                if isOllamaInstalled == false {
                    throw BackendError.processFailed(
                        localized(
                            "Ollama がインストールされていません。",
                            "Ollama is not installed.",
                            "未安装 Ollama。",
                            "Ollama가 설치되어 있지 않습니다."
                        )
                    )
                }

                if isOllamaAvailable, !translationModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    _ = try await translateSingleText(
                        localized("字幕テスト", "Subtitle test", "字幕测试", "자막 테스트"),
                        busyMessage: localized(
                            "翻訳の動作チェック中…",
                            "Checking translation…",
                            "正在检查翻译…",
                            "번역 동작을 확인 중…"
                        )
                    )
                }

                setupDiagnosticSummary = localized(
                    "環境チェックは正常です。Python・Ollama・翻訳経路を確認しました。",
                    "Everything looks good. Python, Ollama, and translation are ready.",
                    "环境检查通过。Python、Ollama 和翻译链路均正常。",
                    "환경 점검이 정상입니다. Python, Ollama, 번역 경로를 확인했습니다."
                )
            } catch {
                setupDiagnosticSummary = error.localizedDescription
                present(error: error)
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

        importSRT(from: url)
    }

    private func importSRT(from url: URL) {
        let previousSnapshot = makeSubtitleUndoSnapshot()

        Task {
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try SubtitleUtilities.parseSRT(url: url)
                }.value
                subtitles = normalizedSubtitles(from: parsed)
                selectedSubtitleID = subtitles.first?.id
                registerUndoSnapshot(previousSnapshot, actionName: "SRT 読み込み")
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
        let previousSnapshot = makeSubtitleUndoSnapshot()

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
                let payload: BackendExtractPayload
                if selectedSourceTranslationLanguage == .japanese {
                    if backend.isUsingBundledBackend {
                        payload = try await NativeOCRExtractor.extract(
                            videoURL: videoURL,
                            region: region,
                            preferences: preferences,
                            language: selectedSourceTranslationLanguage,
                            progressHandler: progressHandler
                        )
                    } else {
                        do {
                            payload = try await backend.extract(
                                videoURL: videoURL,
                                region: region,
                                preferences: preferences,
                                progressHandler: progressHandler
                            )
                        } catch {
                            payload = try await NativeOCRExtractor.extract(
                                videoURL: videoURL,
                                region: region,
                                preferences: preferences,
                                language: selectedSourceTranslationLanguage,
                                progressHandler: progressHandler
                            )
                        }
                    }
                } else {
                    payload = try await NativeOCRExtractor.extract(
                        videoURL: videoURL,
                        region: region,
                        preferences: preferences,
                        language: selectedSourceTranslationLanguage,
                        progressHandler: progressHandler
                    )
                }

                var extractedSubtitles = payload.subtitles
                if ocrRefinementMode != .off && isOllamaAvailable {
                    extractedSubtitles = await refineExtractedSubtitlesWithAI(
                        subtitles: extractedSubtitles,
                        videoURL: videoURL,
                        region: region,
                        language: selectedSourceTranslationLanguage
                    )
                }

                subtitles = normalizedSubtitles(
                    from: extractedSubtitles,
                    duration: payload.video.duration
                )
                videoMetadata = payload.video
                selectedSubtitleID = subtitles.first?.id
                registerUndoSnapshot(previousSnapshot, actionName: "字幕抽出")
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

        let currentSubtitles = subtitles
        let selectedID = selectedSubtitleID
        let previousSnapshot = makeSubtitleUndoSnapshot()

        Task {
            do {
                let translated = try await runSubtitleTranslation(
                    currentSubtitles,
                    busyMessage: "翻訳中です。Ollama の応答を待っています…"
                )

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
                registerUndoSnapshot(previousSnapshot, actionName: "字幕翻訳")
                statusMessage = "翻訳が完了しました。"
                translationProgress = nil
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
            defer {
                isBusy = false
                exportProgress = nil
            }

            do {
                if chosenFormat == .mp4 || chosenFormat == .mov {
                    guard let sourceVideoURL else {
                        throw NSError(
                            domain: "CaptionStudio",
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
                        fontName: effectiveSubtitleFontName,
                        fontSize: CGFloat(subtitleFontSize),
                        outlineWidth: CGFloat(subtitleOutlineWidth),
                        captionStyle: effectiveCaptionVisualStyle,
                        wrapTimingMode: wrapTimingMode,
                        preferredLineCount: preferredLineCount,
                        overlayImage: overlayImage,
                        outputSize: outputSize,
                        videoRect: hasOverlay ? overlayVideoRect : nil,
                        videoOffset: overlayVideoOffset,
                        videoZoom: overlayVideoZoom
                    )

                    exportProgress = ExportProgress(
                        format: chosenFormat,
                        fractionCompleted: 0.0,
                        estimatedRemainingSeconds: nil,
                        elapsedSeconds: 0.0
                    )
                    try await VideoBurnInExporter.export(request) { [weak self] fractionCompleted, estimatedRemainingSeconds, elapsedSeconds in
                        self?.updateExportProgress(
                            ExportProgress(
                                format: chosenFormat,
                                fractionCompleted: fractionCompleted,
                                estimatedRemainingSeconds: estimatedRemainingSeconds,
                                elapsedSeconds: elapsedSeconds
                            )
                        )
                    }
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
        let previousSnapshot = makeSubtitleUndoSnapshot()
        subtitles = normalizedSubtitles(from: subtitles)
        registerUndoSnapshot(previousSnapshot, actionName: "時間補正")
        statusMessage = "時間重なりを補正しました。"
    }

    func addSubtitle() {
        let anchor = selectedSubtitle ?? subtitles.last
        let start = anchor?.endTime ?? 0.0
        let end = start + max(minDuration, 1.0)
        createSubtitle(startTime: start, endTime: end)
    }

    func createSubtitle(startTime: Double, endTime: Double, text: String = "", translated: String = "") {
        let previousSnapshot = makeSubtitleUndoSnapshot()
        let clampedStart = max(0.0, startTime)
        let clampedEnd = max(clampedStart + max(minDuration, 0.2), endTime)
        let subtitle = SubtitleItem(
            index: subtitles.count + 1,
            startTime: clampedStart,
            endTime: clampedEnd,
            text: text,
            translated: translated
        )
        subtitles.append(subtitle)
        subtitles = normalizedSubtitles(from: subtitles)
        if let inserted = subtitles.first(where: { $0.id == subtitle.id }) {
            setSelectedSubtitleIDs([inserted.id], primary: inserted.id, seek: false)
        } else {
            clearSubtitleSelection()
        }
        registerUndoSnapshot(previousSnapshot, actionName: "字幕追加")
        statusMessage = "字幕を追加しました。"
        seekToSelectedSubtitle()
    }

    func duplicateSelectedSubtitles() {
        let orderedSelection = subtitles.filter { selectedSubtitleIDs.contains($0.id) }
            .sorted { $0.startTime < $1.startTime }
        let seedSelection: [SubtitleItem]
        if !orderedSelection.isEmpty {
            seedSelection = orderedSelection
        } else if let selectedSubtitle {
            seedSelection = [selectedSubtitle]
        } else {
            return
        }

        guard let first = seedSelection.first,
              let last = seedSelection.last else {
            return
        }

        let previousSnapshot = makeSubtitleUndoSnapshot()
        let gap = max(minDuration, 0.2)
        let trackEnd = max(subtitles.map(\.endTime).max() ?? last.endTime, last.endTime)
        let insertionOffset = trackEnd + gap - first.startTime
        let duplicated = seedSelection.map { subtitle in
            SubtitleItem(
                index: subtitles.count + 1,
                startTime: subtitle.startTime + insertionOffset,
                endTime: subtitle.endTime + insertionOffset,
                text: subtitle.text,
                translated: subtitle.translated,
                additionalText: subtitle.additionalText,
                confidence: subtitle.confidence,
                isComplete: subtitle.isComplete
            )
        }

        subtitles.append(contentsOf: duplicated)
        subtitles = normalizedSubtitles(from: subtitles)
        let duplicatedIDs = Set(duplicated.map(\.id))
        let insertedIDs = Set(subtitles.filter { duplicatedIDs.contains($0.id) }.map(\.id))
        if let primaryID = duplicated.first?.id {
            setSelectedSubtitleIDs(insertedIDs, primary: primaryID, seek: false)
        }
        registerUndoSnapshot(previousSnapshot, actionName: "字幕複製")
        statusMessage = insertedIDs.count > 1 ? "\(insertedIDs.count)件の字幕を複製しました。" : "字幕を複製しました。"
        seekToSelectedSubtitle()
    }

    func duplicateSubtitle(id: SubtitleItem.ID) {
        guard subtitles.contains(where: { $0.id == id }) else {
            return
        }
        setSelectedSubtitleIDs([id], primary: id, seek: false)
        duplicateSelectedSubtitles()
    }

    func deleteSelectedSubtitle() {
        let idsToDelete = selectedSubtitleIDs.isEmpty ? Set([selectedSubtitleID].compactMap { $0 }) : selectedSubtitleIDs
        guard !idsToDelete.isEmpty else {
            return
        }

        let previousSnapshot = makeSubtitleUndoSnapshot()
        let firstDeletedIndex = subtitles.firstIndex { idsToDelete.contains($0.id) } ?? 0
        subtitles.removeAll { idsToDelete.contains($0.id) }
        subtitles = normalizedSubtitles(from: subtitles)
        let nextIndex = min(firstDeletedIndex, max(subtitles.count - 1, 0))
        let nextSelectionID = subtitles.indices.contains(nextIndex) ? subtitles[nextIndex].id : nil
        if let nextSelectionID {
            setSelectedSubtitleIDs([nextSelectionID], primary: nextSelectionID, seek: false)
        } else {
            clearSubtitleSelection()
        }
        registerUndoSnapshot(previousSnapshot, actionName: "字幕削除")
        statusMessage = idsToDelete.count > 1 ? "\(idsToDelete.count)件の字幕を削除しました。" : "字幕を削除しました。"
        seekToSelectedSubtitle()
    }

    func deleteSubtitle(id: SubtitleItem.ID) {
        guard subtitles.contains(where: { $0.id == id }) else {
            return
        }
        setSelectedSubtitleIDs([id], primary: id, seek: false)
        deleteSelectedSubtitle()
    }

    func resetSubtitleRegion() {
        subtitleRegion = SubtitleUtilities.defaultSubtitleRegion(for: currentVideoCanvasSize)
    }

    func applySelectedSubtitleEdits(
        startText: String,
        endText: String,
        originalText: String,
        translatedText: String
    ) {
        guard let selectedSubtitleID,
              let startTime = SubtitleUtilities.parseTimecode(startText),
              let endTime = SubtitleUtilities.parseTimecode(endText),
              let index = subtitles.firstIndex(where: { $0.id == selectedSubtitleID }) else {
            present(message: "開始時刻と終了時刻を正しく入力してください。")
            return
        }

        let trimmedOriginal = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranslated = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        var updatedSubtitles = subtitles
        updatedSubtitles[index].startTime = startTime
        updatedSubtitles[index].endTime = endTime
        updatedSubtitles[index].text = trimmedOriginal
        updatedSubtitles[index].translated = trimmedTranslated
        updatedSubtitles = normalizedSubtitles(from: updatedSubtitles)
        guard let normalizedIndex = updatedSubtitles.firstIndex(where: { $0.id == selectedSubtitleID }) else {
            return
        }

        let current = subtitles[index]
        let updated = updatedSubtitles[normalizedIndex]
        let timingChanged = abs(current.startTime - updated.startTime) > 0.0005 || abs(current.endTime - updated.endTime) > 0.0005
        let textChanged = current.text != updated.text || current.translated != updated.translated
        guard timingChanged || textChanged else {
            return
        }

        let previousSnapshot = makeSubtitleUndoSnapshot()
        subtitles = updatedSubtitles
        let restoredSelection = selectedSubtitleIDs.isEmpty ? Set([selectedSubtitleID]) : selectedSubtitleIDs
        setSelectedSubtitleIDs(restoredSelection, primary: selectedSubtitleID, seek: false)
        registerUndoSnapshot(previousSnapshot, actionName: "字幕編集")
        statusMessage = "字幕を更新しました。"
        seekToSelectedSubtitle()
    }

    func updateSubtitleTiming(id: SubtitleItem.ID, startTime: Double, endTime: Double) {
        guard let index = subtitles.firstIndex(where: { $0.id == id }) else {
            return
        }

        var updatedSubtitles = subtitles
        updatedSubtitles[index].startTime = startTime
        updatedSubtitles[index].endTime = endTime
        updatedSubtitles = normalizedSubtitles(from: updatedSubtitles)
        guard let normalizedIndex = updatedSubtitles.firstIndex(where: { $0.id == id }) else {
            return
        }

        let current = subtitles[index]
        let updated = updatedSubtitles[normalizedIndex]
        guard abs(current.startTime - updated.startTime) > 0.0005 || abs(current.endTime - updated.endTime) > 0.0005 else {
            return
        }

        let previousSnapshot = makeSubtitleUndoSnapshot()
        subtitles = updatedSubtitles
        let restoredSelection = selectedSubtitleIDs.isEmpty ? Set([id]) : selectedSubtitleIDs
        setSelectedSubtitleIDs(restoredSelection, primary: id, seek: false)
        registerUndoSnapshot(previousSnapshot, actionName: "字幕時間編集")
        statusMessage = "字幕の時間を更新しました。"
    }

    func nudgeSelectedSubtitleStart(by delta: Double) {
        if selectedSubtitleIDs.count > 1,
           let earliestSelected = subtitles
            .filter({ selectedSubtitleIDs.contains($0.id) })
            .min(by: { $0.startTime < $1.startTime }) {
            updateSelectedSubtitlesStart(to: earliestSelected.startTime + delta)
            return
        }

        guard let selectedSubtitleID,
              let index = subtitles.firstIndex(where: { $0.id == selectedSubtitleID }) else {
            return
        }

        let minimumDuration = max(minDuration, 0.2)
        let previousSnapshot = makeSubtitleUndoSnapshot()
        let upperBound = subtitles[index].endTime - minimumDuration
        subtitles[index].startTime = max(0.0, min(upperBound, subtitles[index].startTime + delta))
        subtitles = normalizedSubtitles(from: subtitles)
        self.selectedSubtitleID = selectedSubtitleID
        registerUndoSnapshot(previousSnapshot, actionName: "字幕開始位置調整")
        statusMessage = "字幕の開始位置を調整しました。"
        seekToSelectedSubtitle()
    }

    func nudgeSelectedSubtitleEnd(by delta: Double) {
        if selectedSubtitleIDs.count > 1,
           let latestSelected = subtitles
            .filter({ selectedSubtitleIDs.contains($0.id) })
            .max(by: { $0.endTime < $1.endTime }) {
            updateSelectedSubtitlesEnd(to: latestSelected.endTime + delta)
            return
        }

        guard let selectedSubtitleID,
              let index = subtitles.firstIndex(where: { $0.id == selectedSubtitleID }) else {
            return
        }

        let minimumDuration = max(minDuration, 0.2)
        let maxTrackEnd = playbackDuration > 0
            ? playbackDuration
            : max(subtitles.map(\.endTime).max() ?? subtitles[index].endTime, subtitles[index].endTime)
        let previousSnapshot = makeSubtitleUndoSnapshot()
        let lowerBound = subtitles[index].startTime + minimumDuration
        let explicitEnd = max(lowerBound, min(maxTrackEnd, subtitles[index].endTime + delta))
        subtitles[index].endTime = explicitEnd
        subtitles = normalizedSubtitles(from: subtitles)
        if let normalizedIndex = subtitles.firstIndex(where: { $0.id == selectedSubtitleID }) {
            subtitles[normalizedIndex].endTime = max(subtitles[normalizedIndex].startTime + minimumDuration, explicitEnd)
        }
        self.selectedSubtitleID = selectedSubtitleID
        registerUndoSnapshot(previousSnapshot, actionName: "字幕終了位置調整")
        statusMessage = "字幕の終了位置を調整しました。"
        seekToSelectedSubtitle()
    }

    func updateSelectedSubtitlesStart(to newStartTime: Double) {
        let orderedSelection = subtitles.filter { selectedSubtitleIDs.contains($0.id) }.sorted { $0.startTime < $1.startTime }
        guard orderedSelection.count > 1,
              let firstSelected = orderedSelection.first,
              let index = subtitles.firstIndex(where: { $0.id == firstSelected.id }) else {
            return
        }

        let minimumDuration = max(minDuration, 0.2)
        let snappedStart = snappedTimelineTime(newStartTime, excluding: firstSelected.id)
        let clampedStart = max(0.0, min(subtitles[index].endTime - minimumDuration, snappedStart))
        guard abs(clampedStart - subtitles[index].startTime) > 0.0005 else {
            return
        }

        let previousSnapshot = makeSubtitleUndoSnapshot()
        subtitles[index].startTime = clampedStart
        subtitles = normalizedSubtitles(from: subtitles)
        setSelectedSubtitleIDs(selectedSubtitleIDs, primary: selectedSubtitleID ?? firstSelected.id, seek: false)
        registerUndoSnapshot(previousSnapshot, actionName: "複数字幕開始位置調整")
        statusMessage = "\(orderedSelection.count)件の字幕の先頭を調整しました。"
    }

    func updateSelectedSubtitlesEnd(to newEndTime: Double) {
        let orderedSelection = subtitles.filter { selectedSubtitleIDs.contains($0.id) }.sorted { $0.startTime < $1.startTime }
        guard orderedSelection.count > 1,
              let lastSelected = orderedSelection.last,
              let index = subtitles.firstIndex(where: { $0.id == lastSelected.id }) else {
            return
        }

        let minimumDuration = max(minDuration, 0.2)
        let maxTrackEnd = playbackDuration > 0
            ? playbackDuration
            : max(subtitles.map(\.endTime).max() ?? lastSelected.endTime, lastSelected.endTime, newEndTime)
        let snappedEnd = snappedTimelineTime(newEndTime, excluding: lastSelected.id)
        let clampedEnd = max(subtitles[index].startTime + minimumDuration, min(maxTrackEnd, snappedEnd))
        guard abs(clampedEnd - subtitles[index].endTime) > 0.0005 else {
            return
        }

        let previousSnapshot = makeSubtitleUndoSnapshot()
        subtitles[index].endTime = clampedEnd
        subtitles = normalizedSubtitles(from: subtitles)
        if let normalizedIndex = subtitles.firstIndex(where: { $0.id == lastSelected.id }) {
            subtitles[normalizedIndex].endTime = max(subtitles[normalizedIndex].startTime + minimumDuration, clampedEnd)
        }
        setSelectedSubtitleIDs(selectedSubtitleIDs, primary: selectedSubtitleID ?? lastSelected.id, seek: false)
        registerUndoSnapshot(previousSnapshot, actionName: "複数字幕終了位置調整")
        statusMessage = "\(orderedSelection.count)件の字幕の末尾を調整しました。"
    }

    func updateSubtitleStart(id: SubtitleItem.ID, to newStartTime: Double) {
        guard let index = subtitles.firstIndex(where: { $0.id == id }) else {
            return
        }

        let minimumDuration = max(minDuration, 0.2)
        let snappedStart = snappedTimelineTime(newStartTime, excluding: id)
        let clampedStart = max(0.0, min(subtitles[index].endTime - minimumDuration, snappedStart))
        guard abs(clampedStart - subtitles[index].startTime) > 0.0005 else {
            return
        }

        let previousSnapshot = makeSubtitleUndoSnapshot()
        subtitles[index].startTime = clampedStart
        subtitles = normalizedSubtitles(from: subtitles)
        selectedSubtitleID = id
        registerUndoSnapshot(previousSnapshot, actionName: "字幕開始位置調整")
        statusMessage = "字幕の開始位置を調整しました。"
    }

    func updateSubtitleEnd(id: SubtitleItem.ID, to newEndTime: Double) {
        guard let index = subtitles.firstIndex(where: { $0.id == id }) else {
            return
        }

        let minimumDuration = max(minDuration, 0.2)
        let maxTrackEnd = playbackDuration > 0
            ? playbackDuration
            : max(subtitles.map(\.endTime).max() ?? subtitles[index].endTime, subtitles[index].endTime, newEndTime)
        let snappedEnd = snappedTimelineTime(newEndTime, excluding: id)
        let clampedEnd = max(subtitles[index].startTime + minimumDuration, min(maxTrackEnd, snappedEnd))
        guard abs(clampedEnd - subtitles[index].endTime) > 0.0005 else {
            return
        }

        let previousSnapshot = makeSubtitleUndoSnapshot()
        subtitles[index].endTime = clampedEnd
        subtitles = normalizedSubtitles(from: subtitles)
        if let normalizedIndex = subtitles.firstIndex(where: { $0.id == id }) {
            subtitles[normalizedIndex].endTime = max(subtitles[normalizedIndex].startTime + minimumDuration, clampedEnd)
        }
        selectedSubtitleID = id
        registerUndoSnapshot(previousSnapshot, actionName: "字幕終了位置調整")
        statusMessage = "字幕の終了位置を調整しました。"
    }

    func moveSubtitle(id: SubtitleItem.ID, toStartTime newStartTime: Double) {
        guard let index = subtitles.firstIndex(where: { $0.id == id }) else {
            return
        }

        let currentDuration = max(subtitles[index].endTime - subtitles[index].startTime, max(minDuration, 0.2))
        let maxTrackEnd = playbackDuration > 0
            ? playbackDuration
            : max(subtitles.map(\.endTime).max() ?? subtitles[index].endTime, subtitles[index].endTime, newStartTime + currentDuration)

        var clampedStart = max(0.0, min(maxTrackEnd - currentDuration, newStartTime))
        let snappedStart = snappedTimelineTimeIfNeeded(clampedStart, excluding: id)
        let snappedEnd = snappedTimelineTimeIfNeeded(clampedStart + currentDuration, excluding: id)

        switch (snappedStart, snappedEnd) {
        case let (.some(start), .some(end)):
            let startDelta = abs(start - clampedStart)
            let endDelta = abs(end - (clampedStart + currentDuration))
            if endDelta < startDelta {
                clampedStart = max(0.0, min(maxTrackEnd - currentDuration, end - currentDuration))
            } else {
                clampedStart = max(0.0, min(maxTrackEnd - currentDuration, start))
            }
        case let (.some(start), .none):
            clampedStart = max(0.0, min(maxTrackEnd - currentDuration, start))
        case let (.none, .some(end)):
            clampedStart = max(0.0, min(maxTrackEnd - currentDuration, end - currentDuration))
        case (.none, .none):
            break
        }

        guard abs(clampedStart - subtitles[index].startTime) > 0.0005 else {
            return
        }

        let previousSnapshot = makeSubtitleUndoSnapshot()
        subtitles[index].startTime = clampedStart
        subtitles[index].endTime = clampedStart + currentDuration
        subtitles = normalizedSubtitles(from: subtitles)
        selectedSubtitleID = id
        registerUndoSnapshot(previousSnapshot, actionName: "字幕移動")
        statusMessage = "字幕の位置を移動しました。"
    }

    func moveSelectedSubtitles(anchorID: SubtitleItem.ID, toStartTime newStartTime: Double) {
        let orderedSelection = subtitles.filter { selectedSubtitleIDs.contains($0.id) }
        guard orderedSelection.count > 1,
              orderedSelection.contains(where: { $0.id == anchorID }),
              let anchorSubtitle = orderedSelection.first(where: { $0.id == anchorID }) else {
            moveSubtitle(id: anchorID, toStartTime: newStartTime)
            return
        }

        let selectedIDs = Set(orderedSelection.map(\.id))
        let earliestStart = orderedSelection.map(\.startTime).min() ?? anchorSubtitle.startTime
        let latestEnd = orderedSelection.map(\.endTime).max() ?? anchorSubtitle.endTime
        let groupDuration = latestEnd - earliestStart
        let maxTrackEnd = playbackDuration > 0
            ? playbackDuration
            : max(subtitles.map(\.endTime).max() ?? latestEnd, latestEnd, newStartTime + groupDuration)

        let delta = newStartTime - anchorSubtitle.startTime
        var groupStart = earliestStart + delta
        groupStart = max(0.0, min(maxTrackEnd - groupDuration, groupStart))
        let adjustedDelta = groupStart - earliestStart

        let unselectedBoundaries = subtitles
            .filter { !selectedIDs.contains($0.id) }
            .flatMap { [$0.startTime, $0.endTime] } + [0.0, maxTrackEnd]

        let snappingThreshold = 0.12
        var snappedDelta = adjustedDelta
        for subtitle in orderedSelection {
            for boundary in [subtitle.startTime + adjustedDelta, subtitle.endTime + adjustedDelta] {
                if let candidate = unselectedBoundaries.min(by: { abs($0 - boundary) < abs($1 - boundary) }),
                   abs(candidate - boundary) <= snappingThreshold {
                    snappedDelta += candidate - boundary
                    break
                }
            }
        }

        let finalGroupStart = max(0.0, min(maxTrackEnd - groupDuration, earliestStart + snappedDelta))
        let finalDelta = finalGroupStart - earliestStart
        guard abs(finalDelta - adjustedDelta) > 0.0005 || abs(adjustedDelta) > 0.0005 else {
            return
        }

        let previousSnapshot = makeSubtitleUndoSnapshot()
        subtitles = subtitles.map { subtitle in
            guard selectedIDs.contains(subtitle.id) else {
                return subtitle
            }
            var updated = subtitle
            updated.startTime += finalDelta
            updated.endTime += finalDelta
            return updated
        }
        subtitles = normalizedSubtitles(from: subtitles)
        setSelectedSubtitleIDs(selectedIDs, primary: anchorID, seek: false)
        registerUndoSnapshot(previousSnapshot, actionName: "字幕移動")
        statusMessage = "\(selectedIDs.count)件の字幕を移動しました。"
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
        let previousSnapshot = makeSubtitleUndoSnapshot()

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

        registerUndoSnapshot(previousSnapshot, actionName: "追加字幕")

        if player?.timeControlStatus != .playing {
            seekPlayback(to: target.startTime, pauseAfterSeek: true)
        }
    }

    func translateAdditionalSubtitleText(_ text: String) async throws -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return ""
        }

        return try await translateSingleText(
            normalized,
            busyMessage: "追加字幕を翻訳しています…"
        )
    }

    func retranslateEditedSubtitleText(_ text: String) async -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            present(message: "再翻訳する原文を入力してください。")
            return nil
        }

        do {
            let translated = try await translateSingleText(
                normalized,
                busyMessage: "選択字幕を再翻訳しています…"
            )
            statusMessage = "選択字幕を再翻訳しました。"
            return translated
        } catch {
            present(error: error)
            return nil
        }
    }

    func retranslateSubtitle(id: SubtitleItem.ID) async {
        guard let subtitle = subtitles.first(where: { $0.id == id }) else {
            return
        }

        setSelectedSubtitleIDs([id], primary: id, seek: false)
        guard let translated = await retranslateEditedSubtitleText(subtitle.text) else {
            return
        }
        guard let index = subtitles.firstIndex(where: { $0.id == id }) else {
            return
        }

        let previousSnapshot = makeSubtitleUndoSnapshot()
        subtitles[index].translated = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        subtitles = normalizedSubtitles(from: subtitles)
        setSelectedSubtitleIDs([id], primary: id, seek: false)
        registerUndoSnapshot(previousSnapshot, actionName: "字幕再翻訳")
        statusMessage = "選択字幕を再翻訳しました。"
    }

    func correctEditedSubtitleTextWithAI(_ text: String) async -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            present(message: "AI 補正する原文を入力してください。")
            return nil
        }

        do {
            var preferences = try await resolveTranslationPreferences()
            preferences.customDictionary = ""
            setBusy(true, message: "選択字幕を AI 補正しています…")
            defer { isBusy = false }
            let corrected = try await backend.correctOCRText(
                normalized,
                preferences: preferences
            )
            statusMessage = "選択字幕を AI 補正しました。"
            return corrected
        } catch {
            present(error: error)
            return nil
        }
    }

    func previewImageForRerecognition(
        startText: String,
        endText: String
    ) async -> NSImage? {
        guard let videoURL else {
            return previewImage
        }
        guard let startTime = SubtitleUtilities.parseTimecode(startText),
              let endTime = SubtitleUtilities.parseTimecode(endText),
              endTime > startTime else {
            return previewImage
        }

        let sampleTime = min(max((startTime + endTime) * 0.5, startTime), endTime)
        return await VideoLoader.framePreviewImage(url: videoURL, at: sampleTime) ?? previewImage
    }

    func rerecognizeSelectedSubtitleText(
        startText: String,
        endText: String,
        region: NormalizedRect,
        currentTextHint: String
    ) async -> String? {
        guard let videoURL else {
            present(message: "再認識するには先に動画を開いてください。")
            return nil
        }
        guard let startTime = SubtitleUtilities.parseTimecode(startText),
              let endTime = SubtitleUtilities.parseTimecode(endText),
              endTime > startTime else {
            present(message: "再認識する字幕の開始時刻と終了時刻を正しく入力してください。")
            return nil
        }

        do {
            setBusy(true, message: "選択範囲を AI で再認識しています…")
            extractionProgress = ExtractionProgress(processed: 0, total: 4, timestamp: startTime)
            defer {
                isBusy = false
                extractionProgress = nil
            }
            let progressHandler = ExtractionProgressHandlerBox { [weak self] progress in
                self?.updateExtractionProgress(progress)
            }

            var resolvedText = ""
            if isOllamaAvailable {
                var preferences = try await resolveTranslationPreferences()
                preferences.customDictionary = ""
                let sampledImages = try await VideoLoader.subtitleCropImageBase64Samples(
                    url: videoURL,
                    range: startTime ... endTime,
                    region: region.clamped(),
                    language: selectedSourceTranslationLanguage,
                    maxFrames: 4,
                    progressHandler: progressHandler
                )

                if !sampledImages.isEmpty {
                    let visionModel = preferredVisionModelName(fallback: preferences.model)
                    resolvedText = try await backend.recognizeSubtitleImages(
                        sampledImages,
                        sourceLanguage: selectedSourceTranslationLanguage.rawValue,
                        hintText: currentTextHint,
                        model: visionModel
                    )
                }
            }

            var boostedPreferences = processingPreferences
            boostedPreferences.fpsSample = max(processingPreferences.fpsSample, 6.0)
            if resolvedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                statusMessage = "AI の読み取りが不十分だったため、標準 OCR と AI 補正で再試行しています…"
                let ocrText = try await NativeOCRExtractor.rerecognize(
                    videoURL: videoURL,
                    range: startTime ... endTime,
                    region: region.clamped(),
                    preferences: boostedPreferences,
                    language: selectedSourceTranslationLanguage,
                    progressHandler: progressHandler
                )

                if !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   isOllamaAvailable
                {
                    var preferences = try await resolveTranslationPreferences()
                    preferences.customDictionary = ""
                    resolvedText = try await backend.correctOCRText(
                        ocrText,
                        preferences: preferences
                    )
                } else {
                    resolvedText = ocrText
                }
            }

            let text = resolvedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                present(message: "AI 再認識では有効な字幕を読み取れませんでした。範囲をさらに狭めて再試行してください。")
                return nil
            }
            statusMessage = "選択字幕を AI で再認識しました。"
            return text
        } catch {
            present(error: error)
            return nil
        }
    }

    func rerecognizeSubtitle(id: SubtitleItem.ID, region: NormalizedRect? = nil) async {
        guard let subtitle = subtitles.first(where: { $0.id == id }) else {
            return
        }

        setSelectedSubtitleIDs([id], primary: id, seek: false)
        let startText = SubtitleUtilities.compactTimestamp(subtitle.startTime)
        let endText = SubtitleUtilities.compactTimestamp(subtitle.endTime)
        guard let recognized = await rerecognizeSelectedSubtitleText(
            startText: startText,
            endText: endText,
            region: (region ?? subtitleRegion).clamped(),
            currentTextHint: subtitle.text
        ) else {
            return
        }
        guard let index = subtitles.firstIndex(where: { $0.id == id }) else {
            return
        }

        let previousSnapshot = makeSubtitleUndoSnapshot()
        subtitles[index].text = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        subtitles = normalizedSubtitles(from: subtitles)
        setSelectedSubtitleIDs([id], primary: id, seek: false)
        registerUndoSnapshot(previousSnapshot, actionName: "字幕AI再認識")
        statusMessage = "選択字幕を AI で再認識しました。"
        seekToSelectedSubtitle()
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
            subtitleLanguage: selectedSourceTranslationLanguage.rawValue,
            wrapWidthRatio: effectiveWrapWidthRatio,
            wrapTimingMode: wrapTimingMode,
            preferredLineCount: preferredLineCount,
            subtitleFontSize: subtitleFontSize,
            subtitleFontName: effectiveSubtitleFontName,
            subtitleOutlineWidth: subtitleOutlineWidth
        )
    }

    private var translationPreferences: TranslationPreferences {
        TranslationPreferences(
            model: translationModel,
            customDictionary: activeDictionaryEntriesForCurrentTranslation.compactMap { entry in
                entry.serialized(
                    forSourceLanguage: selectedSourceTranslationLanguage,
                    targetLanguage: selectedTargetTranslationLanguage,
                    useForCurrentVideo: useDictionaryForCurrentProject
                )
            }.joined(separator: "\n"),
            sourceLanguage: selectedSourceTranslationLanguage.rawValue,
            targetLanguage: selectedTargetTranslationLanguage.rawValue,
            useContextualTranslation: useContextualTranslation,
            contextWindow: max(0, translationContextWindow),
            preserveSlangAndTone: preserveSlangAndTone
        )
    }

    private var activeDictionaryEntriesForCurrentTranslation: [DictionaryEntry] {
        guard useDictionaryForCurrentProject else {
            return []
        }
        return dictionaryEntries.filter { entry in
            entry.matches(
                sourceLanguage: selectedSourceTranslationLanguage,
                targetLanguage: selectedTargetTranslationLanguage,
                useForCurrentVideo: useDictionaryForCurrentProject
            )
        }
    }

    private func preferredVisionModelName(fallback: String) -> String {
        let normalizedPreferred = preferredVisionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedPreferred.isEmpty, let resolvedPreferred = resolveInstalledModelName(normalizedPreferred) {
            return resolvedPreferred
        }

        let installed = availableTranslationModels
        let lowercasedFallback = fallback.lowercased()
        let visionHints = ["gemma3", "llava", "bakllava", "moondream", "minicpm-v", "qwen2.5vl", "qwen-vl"]
        if visionHints.contains(where: { lowercasedFallback.contains($0) }) {
            return fallback
        }
        if let preferred = installed.first(where: { model in
            let normalized = model.lowercased()
            return visionHints.contains(where: { normalized.contains($0) })
        }) {
            return preferred
        }
        return fallback
    }

    private func refineExtractedSubtitlesWithAI(
        subtitles: [SubtitleItem],
        videoURL: URL,
        region: NormalizedRect,
        language: TranslationLanguage
    ) async -> [SubtitleItem] {
        guard isOllamaAvailable, !subtitles.isEmpty, ocrRefinementMode != .off else {
            return subtitles
        }

        let visionModel = preferredVisionModelName(fallback: translationModel)
        var refinedSubtitles = subtitles
        let targetIndices = subtitles.indices.filter { index in
            shouldRefineExtractedSubtitle(subtitles[index], language: language)
        }
        guard !targetIndices.isEmpty else {
            return subtitles
        }
        let total = targetIndices.count
        statusMessage = ocrRefinementMode == .aggressive
            ? localized(
                "字幕を AI で高精度に読み直しています…",
                "AI is rereading subtitles in high precision mode…",
                "AI 正在以高精度模式重新读取字幕…",
                "AI가 자막을 고정밀 모드로 다시 읽는 중입니다…"
            )
            : localized(
                "怪しい字幕だけ AI で読み直しています…",
                "AI is rereading suspicious subtitles only…",
                "AI 正在只重读可疑字幕…",
                "수상한 자막만 AI가 다시 읽는 중입니다…"
            )

        for (progressIndex, index) in targetIndices.enumerated() {
            let subtitle = subtitles[index]
            extractionProgress = ExtractionProgress(
                processed: progressIndex,
                total: total,
                timestamp: subtitle.startTime
            )

            do {
                let images = try await VideoLoader.subtitleCropImageBase64Samples(
                    url: videoURL,
                    range: subtitle.startTime ... subtitle.endTime,
                    region: region,
                    language: language,
                    maxFrames: aiRerecognitionFrameCount(for: language)
                )
                guard !images.isEmpty else {
                    continue
                }
                let recognized = try await backend.recognizeSubtitleImages(
                    images,
                    sourceLanguage: language.rawValue,
                    hintText: subtitle.text,
                    model: visionModel
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                guard shouldPreferAIRefinedText(recognized, over: subtitle.text, language: language) else {
                    continue
                }
                refinedSubtitles[index].text = recognized
            } catch {
                continue
            }
        }

        extractionProgress = ExtractionProgress(
            processed: total,
            total: total,
            timestamp: subtitles.last?.endTime ?? 0.0
        )
        return refinedSubtitles
    }

    private func shouldRefineExtractedSubtitle(_ subtitle: SubtitleItem, language: TranslationLanguage) -> Bool {
        let text = subtitle.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return false
        }
        let scriptScore = NativeOCRExtractor.scriptCoverageScore(for: text, language: language)
        let suspiciousArtifacts = containsSuspiciousOCRArtifacts(text, language: language)

        switch ocrRefinementMode {
        case .off:
            return false
        case .smart:
            switch language {
            case .korean:
                return suspiciousArtifacts || scriptScore < 0.93 || text.count <= 4
            case .chinese:
                return suspiciousArtifacts || scriptScore < 0.90 || text.count <= 4
            case .english:
                return suspiciousArtifacts || scriptScore < 0.87 || text.count <= 4
            case .japanese:
                return suspiciousArtifacts || scriptScore < 0.88 || text.count <= 4
            }
        case .aggressive:
            switch language {
            case .korean:
                return true
            case .chinese:
                return suspiciousArtifacts || scriptScore < 0.95 || text.count <= 8
            case .english:
                return suspiciousArtifacts || scriptScore < 0.92 || text.count <= 6
            case .japanese:
                return suspiciousArtifacts || scriptScore < 0.92 || text.count <= 6
            }
        }
    }

    private func aiRerecognitionFrameCount(for language: TranslationLanguage) -> Int {
        switch ocrRefinementMode {
        case .off:
            return 0
        case .smart:
            switch language {
            case .korean:
                return 3
            case .chinese:
                return 3
            case .english, .japanese:
                return 2
            }
        case .aggressive:
            switch language {
            case .korean:
                return 5
            case .chinese:
                return 4
            case .english, .japanese:
                return 3
            }
        }
    }

    private func containsSuspiciousOCRArtifacts(_ text: String, language: TranslationLanguage) -> Bool {
        if text.contains("�") || text.contains("□") || text.contains("○") || text.contains("●") {
            return true
        }

        switch language {
        case .korean:
            return text.range(of: #"(?<=\s|^)[A-Za-z](?=\s|$)"#, options: .regularExpression) != nil
        case .chinese:
            return text.range(of: #"[ぁ-ゖァ-ヺ가-힣]"#, options: .regularExpression) != nil
        case .english:
            return text.range(of: #"[가-힣一-龯ぁ-ゖァ-ヺ]"#, options: .regularExpression) != nil
        case .japanese:
            return false
        }
    }

    private func shouldPreferAIRefinedText(
        _ candidate: String,
        over original: String,
        language: TranslationLanguage
    ) -> Bool {
        let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCandidate.isEmpty else {
            return false
        }
        let candidateScore = NativeOCRExtractor.scriptCoverageScore(for: normalizedCandidate, language: language)
        let originalScore = NativeOCRExtractor.scriptCoverageScore(for: normalizedOriginal, language: language)
        if candidateScore > originalScore + 0.08 {
            return true
        }
        if language == .korean && candidateScore >= originalScore && normalizedCandidate.count >= max(2, normalizedOriginal.count - 1) {
            return true
        }
        return normalizedCandidate != normalizedOriginal && candidateScore >= 0.92
    }

    private static func pullOllamaModel(
        executablePath: String,
        modelName: String,
        lineHandler: @escaping @Sendable (String) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["pull", modelName]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let text = String(data: data, encoding: .utf8) else {
                    return
                }
                let lines = text
                    .split(whereSeparator: \.isNewline)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if let lastLine = lines.last {
                    lineHandler(lastLine)
                }
            }

            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                if process.terminationStatus == 0 {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: BackendError.processFailed("`ollama pull \(modelName)` に失敗しました。"))
                }
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private var hasWorkspaceContent: Bool {
        videoURL != nil || !subtitles.isEmpty || overlayOriginalImage != nil || overlayProcessedImage != nil
    }

    private func makeProjectDocument() -> SubtitleProjectDocument {
        SubtitleProjectDocument(
            savedAt: Date(),
            videoPath: videoURL?.path ?? (videoMetadata?.path.isEmpty == false ? videoMetadata?.path : nil),
            subtitles: subtitles,
            selectedSubtitleID: selectedSubtitleID,
            selectedSubtitleIDs: orderedSubtitleIDs(from: selectedSubtitleIDs),
            persistentState: makePersistentState()
        )
    }

    private func saveProject(to url: URL) {
        do {
            let targetURL = ProjectStore.normalizedProjectURL(for: url)
            let project = makeProjectDocument()
            try ProjectStore.save(project, to: targetURL)
            try? ProjectStore.saveAutosave(project)
            currentProjectURL = targetURL
            hasUnsavedProjectChanges = false
            statusMessage = "プロジェクトを保存しました。"
        } catch {
            present(error: error)
        }
    }

    private func autosaveProjectIfNeeded() {
        guard !suppressPersistence else {
            return
        }

        guard hasWorkspaceContent else {
            try? ProjectStore.clearAutosave()
            return
        }

        do {
            try ProjectStore.saveAutosave(makeProjectDocument())
        } catch {
            statusMessage = "自動保存に失敗しました。"
        }
    }

    private func applyProjectDocument(
        _ document: SubtitleProjectDocument,
        projectURL: URL?,
        restoredFromAutosave: Bool,
        announceStatus: String
    ) async {
        suppressPersistence = true
        defer {
            suppressPersistence = false
            persistStateIfNeeded()
            autosaveProjectIfNeeded()
        }

        clearWorkspace()
        currentProjectURL = projectURL

        if let videoPath = document.videoPath {
            let url = URL(fileURLWithPath: videoPath)
            if FileManager.default.fileExists(atPath: url.path) {
                await loadVideo(from: url)
            }
        }

        applyPersistentState(document.persistentState)
        subtitles = document.subtitles
        let restoredSelectionIDs = Set((document.selectedSubtitleIDs ?? []).filter { id in
            subtitles.contains(where: { $0.id == id })
        })
        if !restoredSelectionIDs.isEmpty {
            setSelectedSubtitleIDs(restoredSelectionIDs, primary: document.selectedSubtitleID, seek: false)
        } else if let selectedSubtitleID = document.selectedSubtitleID,
                  subtitles.contains(where: { $0.id == selectedSubtitleID }) {
            setSelectedSubtitleIDs([selectedSubtitleID], primary: selectedSubtitleID, seek: false)
        } else {
            let fallbackID = subtitles.first?.id
            if let fallbackID {
                setSelectedSubtitleIDs([fallbackID], primary: fallbackID, seek: false)
            } else {
                clearSubtitleSelection()
            }
        }
        hasUnsavedProjectChanges = restoredFromAutosave
        statusMessage = announceStatus
        seekToSelectedSubtitle()
    }

    private func clearWorkspace() {
        overlayProcessingTask?.cancel()
        extractionRegionPreviewTask?.cancel()
        removePlayerTimeObserver()
        player = nil
        videoURL = nil
        videoMetadata = nil
        previewImage = nil
        extractionRegionPreviewImage = nil
        extractionRegionPreviewTask = nil
        extractionRegionPreviewKey = nil
        subtitles = []
        clearSubtitleSelection()
        extractionProgress = nil
        translationProgress = nil
        exportProgress = nil
        playbackTime = 0.0
        playbackScrubTime = 0.0
        isScrubbingPlayback = false
        overlayOriginalImage = nil
        overlayProcessedImage = nil
        overlayFileName = ""
        currentOverlayURL = nil
        overlayVideoRectIsManual = false
        useDictionaryForCurrentProject = true
    }

    private func makeSubtitleUndoSnapshot() -> SubtitleUndoSnapshot {
        SubtitleUndoSnapshot(
            subtitles: subtitles,
            selectedSubtitleID: selectedSubtitleID,
            selectedSubtitleIDs: selectedSubtitleIDs
        )
    }

    private func registerUndoSnapshot(_ snapshot: SubtitleUndoSnapshot, actionName: String) {
        guard snapshot.subtitles != subtitles ||
                snapshot.selectedSubtitleID != selectedSubtitleID ||
                snapshot.selectedSubtitleIDs != selectedSubtitleIDs else {
            return
        }

        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreUndoSnapshot(snapshot, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private func restoreUndoSnapshot(_ snapshot: SubtitleUndoSnapshot, actionName: String) {
        let redoSnapshot = makeSubtitleUndoSnapshot()
        subtitles = snapshot.subtitles
        let restoredSelectionIDs = snapshot.selectedSubtitleIDs.intersection(Set(subtitles.map(\.id)))
        if !restoredSelectionIDs.isEmpty {
            setSelectedSubtitleIDs(restoredSelectionIDs, primary: snapshot.selectedSubtitleID, seek: false)
        } else if let selectedSubtitleID = snapshot.selectedSubtitleID,
                  subtitles.contains(where: { $0.id == selectedSubtitleID }) {
            setSelectedSubtitleIDs([selectedSubtitleID], primary: selectedSubtitleID, seek: false)
        } else {
            let fallbackID = subtitles.first?.id
            if let fallbackID {
                setSelectedSubtitleIDs([fallbackID], primary: fallbackID, seek: false)
            } else {
                clearSubtitleSelection()
            }
        }
        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreUndoSnapshot(redoSnapshot, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        statusMessage = "\(actionName)を元に戻しました。"
        seekToSelectedSubtitle()
    }

    private func orderedSubtitleIDs(from ids: Set<SubtitleItem.ID>) -> [SubtitleItem.ID] {
        subtitles.map(\.id).filter(ids.contains)
    }

    private func sanitizeSubtitleSelection() {
        guard !isSynchronizingSubtitleSelection else {
            return
        }

        let validIDs = Set(subtitles.map(\.id))
        let filteredIDs = selectedSubtitleIDs.intersection(validIDs)

        isSynchronizingSubtitleSelection = true
        if filteredIDs != selectedSubtitleIDs {
            selectedSubtitleIDs = filteredIDs
        }

        if let selectedSubtitleID, validIDs.contains(selectedSubtitleID) {
            if !filteredIDs.isEmpty && !filteredIDs.contains(selectedSubtitleID) {
                self.selectedSubtitleID = orderedSubtitleIDs(from: filteredIDs).first
            }
        } else {
            self.selectedSubtitleID = orderedSubtitleIDs(from: filteredIDs).first
        }
        isSynchronizingSubtitleSelection = false
    }

    private func synchronizeSelectionFromPrimarySelection() {
        guard !isSynchronizingSubtitleSelection else {
            return
        }

        isSynchronizingSubtitleSelection = true
        if let selectedSubtitleID,
           subtitles.contains(where: { $0.id == selectedSubtitleID }) {
            selectedSubtitleIDs = [selectedSubtitleID]
        } else {
            self.selectedSubtitleID = nil
            selectedSubtitleIDs = []
        }
        isSynchronizingSubtitleSelection = false
    }

    private func synchronizePrimarySelectionFromSelectionSet() {
        guard !isSynchronizingSubtitleSelection else {
            return
        }

        let orderedIDs = orderedSubtitleIDs(from: selectedSubtitleIDs)
        let validIDs = Set(orderedIDs)

        isSynchronizingSubtitleSelection = true
        if validIDs != selectedSubtitleIDs {
            selectedSubtitleIDs = validIDs
        }

        if validIDs.isEmpty {
            selectedSubtitleID = nil
        } else if let selectedSubtitleID, validIDs.contains(selectedSubtitleID) {
            self.selectedSubtitleID = selectedSubtitleID
        } else {
            self.selectedSubtitleID = orderedIDs.first
        }
        isSynchronizingSubtitleSelection = false
    }

    private func applyPersistentState(_ state: PersistentAppState) {
        appLanguage = state.appLanguage
        captionStylePreset = state.captionStylePreset
        workspaceLayoutPreset = state.workspaceLayoutPreset
        fpsSample = state.fpsSample
        ocrRefinementMode = state.ocrRefinementMode
        detectScroll = state.detectScroll
        minDuration = state.minDuration
        maxDuration = state.maxDuration
        wrapWidthRatio = state.wrapWidthRatio
        wrapTimingMode = state.wrapTimingMode
        preferredLineCount = max(0, state.preferredLineCount)
        subtitleFontSize = state.subtitleFontSize
        subtitleFontName = state.subtitleFontName
        subtitleOutlineWidth = state.subtitleOutlineWidth
        exportTextMode = state.exportTextMode
        translationModel = state.translationModel
        preferredVisionModel = state.preferredVisionModel
        sourceLanguage = TranslationLanguage(rawValue: state.sourceLanguage)?.rawValue ?? TranslationLanguage.japanese.rawValue
        targetLanguage = TranslationLanguage(rawValue: state.targetLanguage)?.rawValue ?? TranslationLanguage.english.rawValue
        useContextualTranslation = state.useContextualTranslation
        translationContextWindow = max(0, state.translationContextWindow)
        preserveSlangAndTone = state.preserveSlangAndTone
        sharePreReleaseAnalytics = state.sharePreReleaseAnalytics
        includeDiagnosticsInFeedback = state.includeDiagnosticsInFeedback
        automaticallyChecksForUpdates = state.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = state.automaticallyDownloadsUpdates
        includePrereleaseUpdates = state.includePrereleaseUpdates
        updateCheckInterval = state.updateCheckInterval
        lastUpdateCheckAt = state.lastUpdateCheckAt
        dismissedUpdateVersion = state.dismissedUpdateVersion
        downloadedUpdateVersion = state.downloadedUpdateVersion
        if let downloadedUpdatePath = state.downloadedUpdatePath {
            let url = URL(fileURLWithPath: downloadedUpdatePath)
            downloadedUpdateFileURL = FileManager.default.fileExists(atPath: url.path) ? url : nil
            if downloadedUpdateFileURL == nil {
                downloadedUpdateVersion = nil
            }
        } else {
            downloadedUpdateFileURL = nil
        }
        if let downloadedUpdateVersion,
           UpdateChecker.compareVersions(downloadedUpdateVersion, currentVersionString) != .orderedDescending {
            self.downloadedUpdateVersion = nil
            downloadedUpdateFileURL = nil
        }
        useDictionaryForCurrentProject = state.useDictionaryForCurrentProject
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
        overlayEditMode = state.overlayEditMode == .additionalSubtitleWindow ? .subtitleWindow : state.overlayEditMode
        favoriteFontNames = Array(Set(state.favoriteFontNames.filter { !$0.isEmpty })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        overlayPresets = state.overlayPresets.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
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

    private func resolveTranslationPreferences() async throws -> TranslationPreferences {
        let backend = backend
        let runtimePayload = try await Task.detached(priority: .utility) {
            try backend.availableOllamaModels()
        }.value
        applyAvailableTranslationModels(runtimePayload)

        guard runtimePayload.available else {
            throw BackendError.processFailed(ollamaUnavailableMessage)
        }

        let availableModels = Set(runtimePayload.models)
        if !availableModels.isEmpty, !availableModels.contains(translationModel) {
            if let resolvedModel = resolveInstalledModelName(translationModel) {
                translationModel = resolvedModel
            } else {
                throw BackendError.processFailed("選択中のモデル `\(translationModel)` は見つかりません。翻訳タブで検出済みモデルに切り替えてください。")
            }
        }

        return translationPreferences
    }

    private func runSubtitleTranslation(
        _ requestSubtitles: [SubtitleItem],
        busyMessage: String
    ) async throws -> [SubtitleItem] {
        let preferences = try await resolveTranslationPreferences()
        let initialText = requestSubtitles
            .lazy
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""

        setBusy(true, message: busyMessage)
        translationProgress = TranslationProgress(
            processed: 0,
            total: max(requestSubtitles.count, 1),
            currentText: initialText
        )
        defer {
            isBusy = false
            translationProgress = nil
        }

        let progressHandler = TranslationProgressHandlerBox { [weak self] progress in
            self?.updateTranslationProgress(progress)
        }
        return try await backend.translate(
            subtitles: requestSubtitles,
            preferences: preferences,
            progressHandler: progressHandler
        )
    }

    private func translateSingleText(
        _ text: String,
        busyMessage: String
    ) async throws -> String {
        let translated = try await runSubtitleTranslation(
            [
                SubtitleItem(
                    index: 1,
                    startTime: 0.0,
                    endTime: max(minDuration, 1.0),
                    text: text
                ),
            ],
            busyMessage: busyMessage
        )
        return translated.first?.translated.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func resolvedPreviewSubtitleRender() -> PreviewRenderCache {
        guard let activePreviewSubtitle else {
            return PreviewRenderCache(key: "empty-subtitle", layout: .empty, image: nil)
        }

        let sourceText = if exportTextMode == .translated && !activePreviewSubtitle.translated.isEmpty {
            activePreviewSubtitle.translated
        } else {
            activePreviewSubtitle.text
        }

        let regionSize = previewSubtitleRenderSize
        let resolvedFontName = effectiveSubtitleFontName
        let resolvedStyle = effectiveCaptionVisualStyle
        let resolvedFontSize = CGFloat(subtitleFontSize) * CGFloat(resolvedStyle.relativeScale)
        let cacheKey = [
            activePreviewSubtitle.id.uuidString,
            sourceText,
            resolvedFontName,
            String(format: "%.2f", resolvedFontSize),
            String(format: "%.2f", subtitleOutlineWidth),
            exportTextMode.rawValue,
            captionStylePreset.rawValue,
            wrapTimingMode.rawValue,
            String(preferredLineCount),
            String(Int(regionSize.width.rounded())),
            String(Int(regionSize.height.rounded())),
        ].joined(separator: "|")

        if let previewSubtitleRenderCache, previewSubtitleRenderCache.key == cacheKey {
            return previewSubtitleRenderCache
        }

        let layout = SubtitleUtilities.fitSubtitleLayout(
            text: sourceText,
            regionSize: regionSize,
            fontName: resolvedFontName,
            preferredFontSize: resolvedFontSize,
            outlineWidth: CGFloat(subtitleOutlineWidth),
            timingMode: wrapTimingMode,
            preferredLineCount: preferredLineCount
        )

        let image = layout.text.isEmpty ? nil : SubtitleUtilities.subtitleImage(
            text: layout.text,
            size: regionSize,
            fontName: resolvedFontName,
            fontSize: CGFloat(layout.fontSize),
            outlineWidth: CGFloat(layout.outlineWidth),
            style: resolvedStyle
        ).map { NSImage(cgImage: $0, size: NSSize(width: regionSize.width, height: regionSize.height)) }

        let cache = PreviewRenderCache(key: cacheKey, layout: layout, image: image)
        previewSubtitleRenderCache = cache
        return cache
    }

    private func resolvedPreviewAdditionalSubtitleRender() -> PreviewRenderCache {
        guard let activePreviewSubtitle else {
            return PreviewRenderCache(key: "empty-additional-subtitle", layout: .empty, image: nil)
        }

        let text = activePreviewSubtitle.additionalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return PreviewRenderCache(key: "empty-additional-subtitle-\(activePreviewSubtitle.id.uuidString)", layout: .empty, image: nil)
        }

        let regionSize = additionalSubtitleRenderSize
        let cacheKey = [
            activePreviewSubtitle.id.uuidString,
            text,
            subtitleFontName,
            String(format: "%.2f", additionalSubtitleFontSize),
            String(Int(regionSize.width.rounded())),
            String(Int(regionSize.height.rounded())),
        ].joined(separator: "|")

        if let previewAdditionalSubtitleRenderCache, previewAdditionalSubtitleRenderCache.key == cacheKey {
            return previewAdditionalSubtitleRenderCache
        }

        let layout = SubtitleUtilities.fitSubtitleLayout(
            text: text,
            regionSize: regionSize,
            fontName: subtitleFontName,
            preferredFontSize: CGFloat(additionalSubtitleFontSize),
            outlineWidth: 0
        )

        let image = layout.text.isEmpty ? nil : SubtitleUtilities.additionalSubtitleBannerImage(
            text: layout.text,
            size: regionSize,
            fontName: subtitleFontName,
            fontSize: CGFloat(layout.fontSize),
            backgroundOpacity: 0.78
        ).map { NSImage(cgImage: $0, size: NSSize(width: regionSize.width, height: regionSize.height)) }

        let cache = PreviewRenderCache(key: cacheKey, layout: layout, image: image)
        previewAdditionalSubtitleRenderCache = cache
        return cache
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

    private var currentVideoCanvasSize: CGSize {
        if let metadata = videoMetadata, metadata.width > 0, metadata.height > 0 {
            return CGSize(width: metadata.width, height: metadata.height)
        }
        if let previewImage {
            return previewImage.size
        }
        return CGSize(width: 1920, height: 1080)
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

    private func snappedTimelineTime(_ proposed: Double, excluding subtitleID: SubtitleItem.ID, tolerance: Double = 0.12) -> Double {
        let candidates = subtitles
            .filter { $0.id != subtitleID }
            .flatMap { [$0.startTime, $0.endTime] }
            + [0.0]
            + (playbackDuration > 0 ? [playbackDuration] : [])

        guard let closest = candidates.min(by: { abs($0 - proposed) < abs($1 - proposed) }) else {
            return proposed
        }

        return abs(closest - proposed) <= tolerance ? closest : proposed
    }

    private func snappedTimelineTimeIfNeeded(_ proposed: Double, excluding subtitleID: SubtitleItem.ID, tolerance: Double = 0.12) -> Double? {
        let snapped = snappedTimelineTime(proposed, excluding: subtitleID, tolerance: tolerance)
        return abs(snapped - proposed) > 0.0005 ? snapped : nil
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
            extractionRegionPreviewImage = previewImage
            subtitleRegion = SubtitleUtilities.defaultSubtitleRegion(
                for: CGSize(width: loaded.metadata.width, height: loaded.metadata.height)
            )
            if overlayOriginalImage == nil, overlayProcessedImage == nil {
                subtitleLayoutRect = SubtitleUtilities.defaultSubtitleLayoutRect(
                    for: CGSize(width: loaded.metadata.width, height: loaded.metadata.height),
                    wrapWidthRatio: wrapWidthRatio
                )
                overlayVideoRect = SubtitleUtilities.defaultOverlayVideoRect(
                    for: CGSize(width: loaded.metadata.width, height: loaded.metadata.height)
                )
            }
            configurePlayer(AVPlayer(url: url))
            useDictionaryForCurrentProject = true
            subtitles = []
            selectedSubtitleID = nil
            extractionProgress = nil
            playbackTime = 0.0
            playbackScrubTime = 0.0
            isScrubbingPlayback = false
            scheduleExtractionRegionPreviewRefresh(for: 0.0, force: true)
            statusMessage = "動画を開きました。字幕範囲を調整して抽出してください。"
        } catch {
            let filename = url.lastPathComponent
            present(
                message: localized(
                    "動画 `\(filename)` を開けませんでした。破損しているか、この Mac で読めない形式の可能性があります。",
                    "Couldn't open `\(filename)`. The file may be damaged or unsupported on this Mac.",
                    "无法打开 `\(filename)`。文件可能已损坏，或当前 Mac 不支持该格式。",
                    "`\(filename)` 파일을 열 수 없습니다. 파일이 손상되었거나 이 Mac에서 지원하지 않는 형식일 수 있습니다."
                )
            )
        }
    }

    private func configurePlayer(_ newPlayer: AVPlayer?) {
        removePlayerTimeObserver()
        player = newPlayer

        guard let newPlayer else {
            playbackTime = 0.0
            playbackScrubTime = 0.0
            isScrubbingPlayback = false
            extractionRegionPreviewImage = previewImage
            extractionRegionPreviewTask?.cancel()
            extractionRegionPreviewTask = nil
            extractionRegionPreviewKey = nil
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
                    self.scheduleExtractionRegionPreviewRefresh(for: seconds)
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

    private func scheduleExtractionRegionPreviewRefresh(for seconds: Double, force: Bool = false) {
        guard let videoURL else {
            extractionRegionPreviewImage = previewImage
            extractionRegionPreviewTask?.cancel()
            extractionRegionPreviewTask = nil
            extractionRegionPreviewKey = nil
            return
        }

        let quantizedTime = (clampedPlaybackTime(seconds) * 4.0).rounded() / 4.0
        let requestKey = "\(videoURL.path)#\(String(format: "%.2f", quantizedTime))"
        if !force, requestKey == extractionRegionPreviewKey {
            return
        }

        extractionRegionPreviewKey = requestKey
        extractionRegionPreviewTask?.cancel()
        extractionRegionPreviewTask = Task { [weak self] in
            let framePreview = await VideoLoader.framePreviewImage(url: videoURL, at: quantizedTime)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard let self, self.videoURL == videoURL else {
                    return
                }
                self.extractionRegionPreviewImage = framePreview ?? self.previewImage
            }
        }
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

    private func updateTranslationProgress(_ progress: TranslationProgress) {
        translationProgress = progress
        statusMessage = translationProgressText
    }

    private func updateExportProgress(_ progress: ExportProgress) {
        exportProgress = progress
        statusMessage = exportProgressText
    }

    private func setBusy(_ value: Bool, message: String) {
        isBusy = value
        statusMessage = message
        if !value {
            extractionProgress = nil
            translationProgress = nil
            exportProgress = nil
        }
    }

    private func present(error: Error) {
        let friendlyMessage = friendlyErrorDescription(for: error)
        errorMessage = friendlyMessage
        isBusy = false
        extractionProgress = nil
        translationProgress = nil
        exportProgress = nil
        recordFeedbackLog(friendlyMessage, level: .error)
    }

    private func present(message: String) {
        errorMessage = message
        isBusy = false
        extractionProgress = nil
        translationProgress = nil
        exportProgress = nil
        recordFeedbackLog(message, level: .warning)
    }

    private func recordFeedbackLog(_ message: String, level: FeedbackLogLevel) {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        feedbackLogEntries.append(
            FeedbackLogEntry(
                timestamp: Date(),
                level: level,
                message: normalized
            )
        )
        if feedbackLogEntries.count > 60 {
            feedbackLogEntries.removeFirst(feedbackLogEntries.count - 60)
        }
    }

    private func friendlyErrorDescription(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == AVFoundationErrorDomain, nsError.code == -11832 {
            return localized(
                "動画フレームの一部を開けませんでした。先頭や終端に壊れたフレームがある可能性があります。最新版では読めるフレームを使って抽出を続けますが、それでも完全に失敗する場合は別形式へ変換してから試してください。",
                "Some video frames couldn't be opened. The file may contain broken frames near the beginning or end. Caption Studio now continues with readable frames, but if the whole extraction still fails, try converting the video to another format first.",
                "部分视频帧无法打开。文件的开头或结尾可能包含损坏帧。Caption Studio 会尽量使用可读取的帧继续处理，但如果仍然完全失败，请先转换成其他格式再试。",
                "일부 비디오 프레임을 열 수 없습니다. 시작이나 끝 부분에 손상된 프레임이 있을 수 있습니다. Caption Studio는 읽을 수 있는 프레임으로 계속 진행하지만, 그래도 완전히 실패하면 다른 형식으로 변환한 뒤 다시 시도해 주세요."
            )
        }
        if error.localizedDescription == "Cannot Open" || error.localizedDescription == "開けません" {
            return localized(
                "動画を開けませんでした。読み取れないフレームが含まれている可能性があります。別形式への変換や、動画の再書き出しも試してください。",
                "Couldn't open the video. It may contain unreadable frames. Try converting or re-exporting the video and then try again.",
                "无法打开视频。文件中可能包含无法读取的帧。请先尝试转换或重新导出视频。",
                "비디오를 열 수 없습니다. 읽을 수 없는 프레임이 포함되어 있을 수 있습니다. 영상을 다른 형식으로 변환하거나 다시 내보낸 뒤 다시 시도해 주세요."
            )
        }
        return error.localizedDescription
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

    private func performAutomaticUpdateCheckIfNeeded() async {
        guard automaticallyChecksForUpdates else {
            return
        }

        guard shouldPerformAutomaticUpdateCheck() else {
            return
        }

        checkForUpdates(userInitiated: false)
    }

    private func shouldPerformAutomaticUpdateCheck(now: Date = Date()) -> Bool {
        guard automaticallyChecksForUpdates, !isCheckingForUpdates, !isDownloadingUpdate else {
            return false
        }

        guard let lastUpdateCheckAt else {
            return true
        }

        return now.timeIntervalSince(lastUpdateCheckAt) >= updateCheckInterval.minimumInterval
    }

    private func shouldPresentUpdate(version: String) -> Bool {
        version != dismissedUpdateVersion
    }

    private func downloadUpdate(
        _ update: AppUpdateInfo,
        openInstallerAfterDownload: Bool
    ) async throws {
        guard !isDownloadingUpdate else {
            return
        }

        if let storedUpdateURL = UpdateInstaller.storedUpdateURL(for: update) {
            downloadedUpdateFileURL = storedUpdateURL
            downloadedUpdateVersion = update.version
            updateDownloadProgress = 1.0
            updateRuntimeSummary = localized(
                "新しいバージョン \(update.version) はダウンロード済みです。",
                "Version \(update.version) is already downloaded.",
                "新版本 \(update.version) 已经下载完成。",
                "새 버전 \(update.version) 이 이미 다운로드되었습니다."
            )
            if openInstallerAfterDownload {
                installDownloadedUpdate()
            }
            return
        }

        isDownloadingUpdate = true
        updateDownloadProgress = 0.0
        updateRuntimeSummary = localized(
            "バージョン \(update.version) をダウンロードしています…",
            "Downloading version \(update.version)…",
            "正在下载版本 \(update.version)…",
            "버전 \(update.version) 다운로드 중…"
        )

        defer {
            isDownloadingUpdate = false
        }

        let fileURL = try await UpdateInstaller.downloadAndStore(update: update) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.updateDownloadProgress = progress
            }
        }

        downloadedUpdateFileURL = fileURL
        downloadedUpdateVersion = update.version
        updateDownloadProgress = 1.0
        availableUpdate = update
        dismissedUpdateVersion = nil
        updateRuntimeSummary = localized(
            "バージョン \(update.version) のインストーラーを保存しました。",
            "The installer for version \(update.version) is ready.",
            "版本 \(update.version) 的安装包已经准备好。",
            "버전 \(update.version) 설치 파일이 준비되었습니다."
        )
        statusMessage = localized(
            "アップデートの準備ができました。インストーラーを開いて更新できます。",
            "The update is ready. Open the installer to continue.",
            "更新已准备好，可以打开安装程序继续。",
            "업데이트 준비가 끝났습니다. 설치 프로그램을 열어 진행하세요."
        )

        if openInstallerAfterDownload {
            installDownloadedUpdate()
        }

        persistStateIfNeeded()
        refreshUpdateRuntimeSummary()
    }

    private func setupPersistence() {
        let persistencePublishers: [AnyPublisher<Void, Never>] = [
            $appLanguage.map { _ in () }.eraseToAnyPublisher(),
            $captionStylePreset.map { _ in () }.eraseToAnyPublisher(),
            $workspaceLayoutPreset.map { _ in () }.eraseToAnyPublisher(),
            $fpsSample.map { _ in () }.eraseToAnyPublisher(),
            $ocrRefinementMode.map { _ in () }.eraseToAnyPublisher(),
            $detectScroll.map { _ in () }.eraseToAnyPublisher(),
            $minDuration.map { _ in () }.eraseToAnyPublisher(),
            $maxDuration.map { _ in () }.eraseToAnyPublisher(),
            $wrapWidthRatio.map { _ in () }.eraseToAnyPublisher(),
            $wrapTimingMode.map { _ in () }.eraseToAnyPublisher(),
            $preferredLineCount.map { _ in () }.eraseToAnyPublisher(),
            $subtitleFontSize.map { _ in () }.eraseToAnyPublisher(),
            $subtitleFontName.map { _ in () }.eraseToAnyPublisher(),
            $subtitleOutlineWidth.map { _ in () }.eraseToAnyPublisher(),
            $exportTextMode.map { _ in () }.eraseToAnyPublisher(),
            $translationModel.map { _ in () }.eraseToAnyPublisher(),
            $preferredVisionModel.map { _ in () }.eraseToAnyPublisher(),
            $sourceLanguage.map { _ in () }.eraseToAnyPublisher(),
            $targetLanguage.map { _ in () }.eraseToAnyPublisher(),
            $useContextualTranslation.map { _ in () }.eraseToAnyPublisher(),
            $translationContextWindow.map { _ in () }.eraseToAnyPublisher(),
            $preserveSlangAndTone.map { _ in () }.eraseToAnyPublisher(),
            $sharePreReleaseAnalytics.map { _ in () }.eraseToAnyPublisher(),
            $includeDiagnosticsInFeedback.map { _ in () }.eraseToAnyPublisher(),
            $automaticallyChecksForUpdates.map { _ in () }.eraseToAnyPublisher(),
            $automaticallyDownloadsUpdates.map { _ in () }.eraseToAnyPublisher(),
            $includePrereleaseUpdates.map { _ in () }.eraseToAnyPublisher(),
            $updateCheckInterval.map { _ in () }.eraseToAnyPublisher(),
            $lastUpdateCheckAt.map { _ in () }.eraseToAnyPublisher(),
            $downloadedUpdateVersion.map { _ in () }.eraseToAnyPublisher(),
            $downloadedUpdateFileURL.map { _ in () }.eraseToAnyPublisher(),
            $useDictionaryForCurrentProject.map { _ in () }.eraseToAnyPublisher(),
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
            $subtitles.map { _ in () }.eraseToAnyPublisher(),
            $selectedSubtitleID.map { _ in () }.eraseToAnyPublisher(),
            $selectedSubtitleIDs.map { _ in () }.eraseToAnyPublisher(),
            $videoURL.map { _ in () }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(persistencePublishers)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                self.persistStateIfNeeded()
                if self.hasWorkspaceContent {
                    self.hasUnsavedProjectChanges = true
                }
                self.autosaveProjectIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func persistStateIfNeeded() {
        guard !suppressPersistence else {
            return
        }

        do {
            let state = makePersistentState()
            let encoded = try JSONEncoder().encode(state)
            try PersistentStateStore.save(state)
            UserDefaults.standard.set(encoded, forKey: persistentStateDefaultsKey)
            UserDefaults.standard.set(appLanguage.rawValue, forKey: AppLanguage.defaultsKey)
            persistImportedFonts()
        } catch {
            statusMessage = "設定の保存に失敗しました。"
        }
    }

    private func makePersistentState() -> PersistentAppState {
        var state = PersistentAppState()
        state.appLanguage = appLanguage
        state.captionStylePreset = captionStylePreset
        state.workspaceLayoutPreset = workspaceLayoutPreset
        state.fpsSample = fpsSample
        state.ocrRefinementMode = ocrRefinementMode
        state.detectScroll = detectScroll
        state.minDuration = minDuration
        state.maxDuration = maxDuration
        state.wrapWidthRatio = wrapWidthRatio
        state.wrapTimingMode = wrapTimingMode
        state.preferredLineCount = preferredLineCount
        state.subtitleFontSize = subtitleFontSize
        state.subtitleFontName = subtitleFontName
        state.subtitleOutlineWidth = subtitleOutlineWidth
        state.exportTextMode = exportTextMode
        state.translationModel = translationModel
        state.preferredVisionModel = preferredVisionModel
        state.sourceLanguage = sourceLanguage
        state.targetLanguage = targetLanguage
        state.useContextualTranslation = useContextualTranslation
        state.translationContextWindow = max(0, translationContextWindow)
        state.preserveSlangAndTone = preserveSlangAndTone
        state.sharePreReleaseAnalytics = sharePreReleaseAnalytics
        state.includeDiagnosticsInFeedback = includeDiagnosticsInFeedback
        state.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        state.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        state.includePrereleaseUpdates = includePrereleaseUpdates
        state.updateCheckInterval = updateCheckInterval
        state.lastUpdateCheckAt = lastUpdateCheckAt
        state.dismissedUpdateVersion = dismissedUpdateVersion
        state.downloadedUpdateVersion = downloadedUpdateVersion
        state.downloadedUpdatePath = downloadedUpdateFileURL?.path
        state.useDictionaryForCurrentProject = useDictionaryForCurrentProject
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
        state.overlayEditMode = overlayEditMode == .additionalSubtitleWindow ? .subtitleWindow : overlayEditMode
        state.favoriteFontNames = favoriteFontNames
        state.importedFontPaths = importedFontFiles.map(\.path)
        state.overlayPresets = overlayPresets
        state.currentOverlayPath = currentOverlayURL?.path
        return state
    }

    private func restorePersistentState() {
        let fileState = try? PersistentStateStore.load()
        let userDefaultsState = UserDefaults.standard.data(forKey: persistentStateDefaultsKey)
            .flatMap { try? JSONDecoder().decode(PersistentAppState.self, from: $0) }

        if let storedState = fileState ?? userDefaultsState {
            applyPersistentState(storedState)
            restoreImportedFonts(
                from: storedState.importedFontPaths,
                fallbackToLegacyDefaults: fileState == nil
            )
            UserDefaults.standard.set(appLanguage.rawValue, forKey: AppLanguage.defaultsKey)
            if fileState == nil {
                try? PersistentStateStore.save(makePersistentState())
            }
            refreshUpdateRuntimeSummary()
            return
        }

        restoreImportedFonts(from: [], fallbackToLegacyDefaults: true)
        try? PersistentStateStore.save(makePersistentState())
    }

    private func applyAvailableTranslationModels(_ payload: BackendOllamaModelsPayload?) {
        let models = payload?.models
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } ?? []

        isOllamaAvailable = payload?.available ?? false
        availableTranslationModels = models

        if let payload, payload.available {
            if models.isEmpty {
                translationRuntimeSummary = localized(
                    "Ollama は起動中ですが、利用可能なモデルがありません。",
                    "Ollama is running, but no models are installed.",
                    "Ollama 已启动，但没有安装可用模型。",
                    "Ollama는 실행 중이지만 설치된 모델이 없습니다."
                )
            } else {
                translationRuntimeSummary = localized(
                    "Ollama: \(models.count) モデルを検出",
                    "Ollama: \(models.count) model(s) detected",
                    "Ollama：检测到 \(models.count) 个模型",
                    "Ollama: \(models.count)개 모델 감지"
                )
            }
        } else {
            translationRuntimeSummary = localized(
                "Ollama が見つかりません。'ollama serve' を確認してください。",
                "Ollama is unavailable. Check `ollama serve`.",
                "找不到 Ollama。请确认 `ollama serve`。",
                "Ollama를 찾을 수 없습니다. `ollama serve` 를 확인하세요."
            )
        }

        if translationModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            translationModel = models.first ?? "gemma3:4b"
        } else if !models.isEmpty, !models.contains(translationModel) {
            translationModel = resolveInstalledModelName(translationModel) ?? models.first ?? translationModel
        }

        if !preferredVisionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !models.isEmpty,
           !hasInstalledOllamaModel(preferredVisionModel)
        {
            preferredVisionModel = ""
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

    private func restoreImportedFonts(from storedPaths: [String], fallbackToLegacyDefaults: Bool) {
        let resolvedStoredPaths: [String]
        if !storedPaths.isEmpty {
            resolvedStoredPaths = storedPaths
        } else if fallbackToLegacyDefaults {
            resolvedStoredPaths = UserDefaults.standard.stringArray(forKey: importedFontsDefaultsKey) ?? []
        } else {
            resolvedStoredPaths = []
        }

        let urls = resolvedStoredPaths.map(URL.init(fileURLWithPath:)).filter { FileManager.default.fileExists(atPath: $0.path) }
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

    private func localized(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        appLanguage.pick(japanese, english, chinese, korean)
    }

    private func refreshUpdateRuntimeSummary() {
        guard !isCheckingForUpdates, !isDownloadingUpdate else {
            return
        }

        if let availableUpdate {
            if hasDownloadedUpdateReady {
                updateRuntimeSummary = localized(
                    "新しいバージョン \(availableUpdate.version) はダウンロード済みです。",
                    "Version \(availableUpdate.version) is already downloaded.",
                    "新版本 \(availableUpdate.version) 已下载完成。",
                    "새 버전 \(availableUpdate.version) 이 이미 다운로드되었습니다."
                )
            } else {
                updateRuntimeSummary = localized(
                    "新しいバージョン \(availableUpdate.version) があります。",
                    "Version \(availableUpdate.version) is available.",
                    "有新版本 \(availableUpdate.version)。",
                    "새 버전 \(availableUpdate.version) 이 있습니다."
                )
            }
            return
        }

        if let downloadedUpdateVersion, downloadedUpdateFileURL != nil {
            updateRuntimeSummary = localized(
                "バージョン \(downloadedUpdateVersion) のインストーラーは保存済みです。",
                "Installer for version \(downloadedUpdateVersion) is already saved.",
                "版本 \(downloadedUpdateVersion) 的安装包已经保存。",
                "버전 \(downloadedUpdateVersion) 설치 파일이 이미 저장되어 있습니다."
            )
            return
        }

        if let lastUpdateCheckAt {
            updateRuntimeSummary = localized(
                "最後に \(lastUpdateCheckAt.formatted(date: .abbreviated, time: .shortened)) に確認しました。",
                "Last checked on \(lastUpdateCheckAt.formatted(date: .abbreviated, time: .shortened)).",
                "上次检查时间：\(lastUpdateCheckAt.formatted(date: .abbreviated, time: .shortened))。",
                "마지막 확인: \(lastUpdateCheckAt.formatted(date: .abbreviated, time: .shortened))."
            )
            return
        }

        updateRuntimeSummary = localized(
            "更新確認待ち",
            "Waiting to check for updates",
            "等待检查更新",
            "업데이트 확인 대기 중"
        )
    }
}
