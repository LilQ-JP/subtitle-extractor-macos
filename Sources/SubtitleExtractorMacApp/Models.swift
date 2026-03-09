import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case srt
    case fcpxml
    case mp4
    case mov

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .srt:
            return "SRT"
        case .fcpxml:
            return "FCPXML"
        case .mp4:
            return "MP4"
        case .mov:
            return "MOV"
        }
    }

    var suggestedFilenameExtension: String {
        rawValue
    }

    var contentType: UTType {
        switch self {
        case .srt:
            return UTType(filenameExtension: "srt") ?? .plainText
        case .fcpxml:
            return UTType(filenameExtension: "fcpxml") ?? .xml
        case .mp4:
            return .mpeg4Movie
        case .mov:
            return .quickTimeMovie
        }
    }
}

enum ExportTextMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case original
    case translated

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original:
            return "原文"
        case .translated:
            return "翻訳字幕"
        }
    }
}

enum OverlayEditMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case videoPosition
    case videoWindow
    case subtitleWindow
    case additionalSubtitleWindow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .videoPosition:
            return "動画位置"
        case .videoWindow:
            return "動画窓"
        case .subtitleWindow:
            return "字幕枠"
        case .additionalSubtitleWindow:
            return "追加字幕"
        }
    }

    var instruction: String {
        switch self {
        case .videoPosition:
            return "透明窓の上をドラッグして動画を移動します。ズームは右のスライダで調整します。"
        case .videoWindow:
            return "ステージ上をドラッグして、動画をはめる窓を描き直します。"
        case .subtitleWindow:
            return "ステージ上をドラッグして、字幕を収める枠を描き直します。"
        case .additionalSubtitleWindow:
            return "ステージ上をドラッグして、追加字幕の帯を表示する位置と大きさを決めます。"
        }
    }
}

struct NormalizedRect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let defaultSubtitleArea = NormalizedRect(
        x: 0.08,
        y: 0.72,
        width: 0.84,
        height: 0.18
    )

    static let defaultAdditionalBannerArea = NormalizedRect(
        x: 0.03,
        y: 0.05,
        width: 0.94,
        height: 0.14
    )

    func clamped() -> NormalizedRect {
        let clampedWidth = min(max(width, 0.05), 1.0)
        let clampedHeight = min(max(height, 0.05), 1.0)
        let clampedX = min(max(x, 0.0), 1.0 - clampedWidth)
        let clampedY = min(max(y, 0.0), 1.0 - clampedHeight)
        return NormalizedRect(
            x: clampedX,
            y: clampedY,
            width: clampedWidth,
            height: clampedHeight
        )
    }
}

struct SubtitleItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var index: Int
    var startTime: Double
    var endTime: Double
    var text: String
    var translated: String = ""
    var additionalText: String = ""
    var confidence: Double = 1.0
    var isComplete: Bool = true

    enum CodingKeys: String, CodingKey {
        case index
        case startTime = "start_time"
        case endTime = "end_time"
        case text
        case translated
        case additionalText = "additional_text"
        case confidence
        case isComplete = "is_complete"
    }

    init(
        id: UUID = UUID(),
        index: Int,
        startTime: Double,
        endTime: Double,
        text: String,
        translated: String = "",
        additionalText: String = "",
        confidence: Double = 1.0,
        isComplete: Bool = true
    ) {
        self.id = id
        self.index = index
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.translated = translated
        self.additionalText = additionalText
        self.confidence = confidence
        self.isComplete = isComplete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        index = try container.decode(Int.self, forKey: .index)
        startTime = try container.decode(Double.self, forKey: .startTime)
        endTime = try container.decode(Double.self, forKey: .endTime)
        text = try container.decode(String.self, forKey: .text)
        translated = try container.decodeIfPresent(String.self, forKey: .translated) ?? ""
        additionalText = try container.decodeIfPresent(String.self, forKey: .additionalText) ?? ""
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 1.0
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(text, forKey: .text)
        try container.encode(translated, forKey: .translated)
        try container.encode(additionalText, forKey: .additionalText)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(isComplete, forKey: .isComplete)
    }
}

struct AdditionalSubtitleDraftTarget: Identifiable, Hashable, Sendable {
    let id = UUID()
    var subtitleID: SubtitleItem.ID?
    var subtitleIndex: Int?
    var playbackTime: Double
    var startTime: Double
    var endTime: Double
    var existingText: String = ""

    var isUpdatingExistingSubtitle: Bool {
        subtitleID != nil
    }
}

struct VideoMetadata: Codable, Hashable, Sendable {
    var path: String
    var width: Int
    var height: Int
    var fps: Double
    var duration: Double
}

struct LoadedVideoAsset: Sendable {
    var metadata: VideoMetadata
    var previewTIFFData: Data?
}

struct ProcessingPreferences: Codable, Hashable, Sendable {
    var fpsSample: Double = 2.0
    var detectScroll: Bool = true
    var minDuration: Double = 0.5
    var maxDuration: Double = 10.0
    var wrapWidthRatio: Double = 0.68
    var subtitleFontSize: Double = 24.0
    var subtitleFontName: String = "Hiragino Sans"
    var subtitleOutlineWidth: Double = 4.0
}

struct RGBColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let greenScreen = RGBColor(red: 0.0, green: 1.0, blue: 0.0)
}

struct DictionaryEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var source: String = ""
    var target: String = ""

    var isComplete: Bool {
        !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var serialized: String? {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSource.isEmpty, !normalizedTarget.isEmpty else {
            return nil
        }
        return "\(normalizedSource)=\(normalizedTarget)"
    }
}

enum TranslationTargetLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case english = "en"
    case chinese = "zh"
    case korean = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "英語"
        case .chinese:
            return "中国語"
        case .korean:
            return "韓国語"
        }
    }
}

struct TranslationPreferences: Codable, Hashable, Sendable {
    var model: String = "gemma3:4b"
    var customDictionary: String = ""
    var sourceLanguage: String = "ja"
    var targetLanguage: String = "en"
}

struct ExportPreferences: Codable, Hashable, Sendable {
    var format: ExportFormat = .srt
    var textMode: ExportTextMode = .translated
}

struct BackendExtractPayload: Codable, Sendable {
    var subtitles: [SubtitleItem]
    var video: VideoMetadata
}

struct BackendSubtitlesPayload: Codable, Sendable {
    var subtitles: [SubtitleItem]
}

struct BackendRuntimeReport: Codable, Sendable {
    var python: String
    var missingModules: [String]

    var isReady: Bool {
        missingModules.isEmpty
    }

    var summary: String {
        if missingModules.isEmpty {
            return "Python 環境: 利用可能 (\(python))"
        }
        let joined = missingModules.joined(separator: ", ")
        return "不足モジュール: \(joined)"
    }
}

struct BackendOllamaModelsPayload: Codable, Sendable {
    var available: Bool
    var models: [String]
}

struct ExtractionProgress: Hashable, Sendable {
    var processed: Int
    var total: Int
    var timestamp: Double

    var fractionCompleted: Double {
        guard total > 0 else {
            return 0.0
        }
        return min(max(Double(processed) / Double(total), 0.0), 1.0)
    }
}

struct BackendExtractProgressPayload: Codable, Sendable {
    var event: String
    var processed: Int
    var total: Int
    var timestamp: Double
}

struct OverlayProcessingResult: Sendable {
    var processedTIFFData: Data?
    var transparentRect: NormalizedRect?
    var detectedKeyColor: RGBColor
}

struct FittedSubtitleLayout: Hashable, Sendable {
    var text: String
    var fontSize: Double
    var outlineWidth: Double

    static let empty = FittedSubtitleLayout(text: "", fontSize: 24.0, outlineWidth: 4.0)
}

struct SavedSize: Codable, Hashable, Sendable {
    var width: Double = 0.0
    var height: Double = 0.0

    init(width: Double = 0.0, height: Double = 0.0) {
        self.width = width
        self.height = height
    }

    init(_ size: CGSize) {
        self.width = size.width
        self.height = size.height
    }

    var cgSize: CGSize {
        CGSize(width: width, height: height)
    }
}

struct OverlayPreset: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var path: String
    var keyColor: RGBColor
    var tolerance: Double
    var softness: Double
    var videoRect: NormalizedRect
    var videoOffset: SavedSize
    var videoZoom: Double
    var subtitleRect: NormalizedRect
    var additionalSubtitleRect: NormalizedRect = .defaultAdditionalBannerArea

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case keyColor
        case tolerance
        case softness
        case videoRect
        case videoOffset
        case videoZoom
        case subtitleRect
        case additionalSubtitleRect
    }

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        keyColor: RGBColor,
        tolerance: Double,
        softness: Double,
        videoRect: NormalizedRect,
        videoOffset: SavedSize,
        videoZoom: Double,
        subtitleRect: NormalizedRect,
        additionalSubtitleRect: NormalizedRect = .defaultAdditionalBannerArea
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.keyColor = keyColor
        self.tolerance = tolerance
        self.softness = softness
        self.videoRect = videoRect
        self.videoOffset = videoOffset
        self.videoZoom = videoZoom
        self.subtitleRect = subtitleRect
        self.additionalSubtitleRect = additionalSubtitleRect
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        keyColor = try container.decode(RGBColor.self, forKey: .keyColor)
        tolerance = try container.decode(Double.self, forKey: .tolerance)
        softness = try container.decode(Double.self, forKey: .softness)
        videoRect = try container.decode(NormalizedRect.self, forKey: .videoRect)
        videoOffset = try container.decodeIfPresent(SavedSize.self, forKey: .videoOffset) ?? SavedSize()
        videoZoom = try container.decodeIfPresent(Double.self, forKey: .videoZoom) ?? 1.0
        subtitleRect = try container.decode(NormalizedRect.self, forKey: .subtitleRect)
        additionalSubtitleRect = try container.decodeIfPresent(NormalizedRect.self, forKey: .additionalSubtitleRect) ?? .defaultAdditionalBannerArea
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(keyColor, forKey: .keyColor)
        try container.encode(tolerance, forKey: .tolerance)
        try container.encode(softness, forKey: .softness)
        try container.encode(videoRect, forKey: .videoRect)
        try container.encode(videoOffset, forKey: .videoOffset)
        try container.encode(videoZoom, forKey: .videoZoom)
        try container.encode(subtitleRect, forKey: .subtitleRect)
        try container.encode(additionalSubtitleRect, forKey: .additionalSubtitleRect)
    }

    var fileURL: URL {
        URL(fileURLWithPath: path)
    }
}

struct PersistentAppState: Codable, Hashable, Sendable {
    var fpsSample: Double = 2.0
    var detectScroll: Bool = true
    var minDuration: Double = 0.5
    var maxDuration: Double = 10.0
    var wrapWidthRatio: Double = 0.68
    var subtitleFontSize: Double = 24.0
    var subtitleFontName: String = "Hiragino Sans"
    var subtitleOutlineWidth: Double = 4.0
    var exportTextMode: ExportTextMode = .translated
    var translationModel: String = "gemma3:4b"
    var sourceLanguage: String = "ja"
    var targetLanguage: String = "en"
    var dictionaryEntries: [DictionaryEntry] = []
    var subtitleRegion: NormalizedRect = .defaultSubtitleArea
    var overlayKeyColor: RGBColor = .greenScreen
    var overlayTolerance: Double = 0.16
    var overlaySoftness: Double = 0.08
    var overlayVideoRect = NormalizedRect(x: 0.08, y: 0.08, width: 0.84, height: 0.72)
    var overlayVideoOffset = SavedSize()
    var overlayVideoZoom: Double = 1.0
    var subtitleLayoutRect = NormalizedRect(x: 0.08, y: 0.86, width: 0.84, height: 0.10)
    var additionalSubtitleLayoutRect = NormalizedRect.defaultAdditionalBannerArea
    var overlayEditMode: OverlayEditMode = .videoPosition
    var favoriteFontNames: [String] = []
    var overlayPresets: [OverlayPreset] = []
    var currentOverlayPath: String?

    enum CodingKeys: String, CodingKey {
        case fpsSample
        case detectScroll
        case minDuration
        case maxDuration
        case wrapWidthRatio
        case subtitleFontSize
        case subtitleFontName
        case subtitleOutlineWidth
        case exportTextMode
        case translationModel
        case sourceLanguage
        case targetLanguage
        case dictionaryEntries
        case subtitleRegion
        case overlayKeyColor
        case overlayTolerance
        case overlaySoftness
        case overlayVideoRect
        case overlayVideoOffset
        case overlayVideoZoom
        case subtitleLayoutRect
        case additionalSubtitleLayoutRect
        case overlayEditMode
        case favoriteFontNames
        case overlayPresets
        case currentOverlayPath
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fpsSample = try container.decodeIfPresent(Double.self, forKey: .fpsSample) ?? 2.0
        detectScroll = try container.decodeIfPresent(Bool.self, forKey: .detectScroll) ?? true
        minDuration = try container.decodeIfPresent(Double.self, forKey: .minDuration) ?? 0.5
        maxDuration = try container.decodeIfPresent(Double.self, forKey: .maxDuration) ?? 10.0
        wrapWidthRatio = try container.decodeIfPresent(Double.self, forKey: .wrapWidthRatio) ?? 0.68
        subtitleFontSize = try container.decodeIfPresent(Double.self, forKey: .subtitleFontSize) ?? 24.0
        subtitleFontName = try container.decodeIfPresent(String.self, forKey: .subtitleFontName) ?? "Hiragino Sans"
        subtitleOutlineWidth = try container.decodeIfPresent(Double.self, forKey: .subtitleOutlineWidth) ?? 4.0
        exportTextMode = try container.decodeIfPresent(ExportTextMode.self, forKey: .exportTextMode) ?? .translated
        translationModel = try container.decodeIfPresent(String.self, forKey: .translationModel) ?? "gemma3:4b"
        sourceLanguage = try container.decodeIfPresent(String.self, forKey: .sourceLanguage) ?? "ja"
        targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "en"
        dictionaryEntries = try container.decodeIfPresent([DictionaryEntry].self, forKey: .dictionaryEntries) ?? []
        subtitleRegion = try container.decodeIfPresent(NormalizedRect.self, forKey: .subtitleRegion) ?? .defaultSubtitleArea
        overlayKeyColor = try container.decodeIfPresent(RGBColor.self, forKey: .overlayKeyColor) ?? .greenScreen
        overlayTolerance = try container.decodeIfPresent(Double.self, forKey: .overlayTolerance) ?? 0.16
        overlaySoftness = try container.decodeIfPresent(Double.self, forKey: .overlaySoftness) ?? 0.08
        overlayVideoRect = try container.decodeIfPresent(NormalizedRect.self, forKey: .overlayVideoRect) ?? NormalizedRect(x: 0.08, y: 0.08, width: 0.84, height: 0.72)
        overlayVideoOffset = try container.decodeIfPresent(SavedSize.self, forKey: .overlayVideoOffset) ?? SavedSize()
        overlayVideoZoom = try container.decodeIfPresent(Double.self, forKey: .overlayVideoZoom) ?? 1.0
        subtitleLayoutRect = try container.decodeIfPresent(NormalizedRect.self, forKey: .subtitleLayoutRect) ?? NormalizedRect(x: 0.08, y: 0.86, width: 0.84, height: 0.10)
        additionalSubtitleLayoutRect = try container.decodeIfPresent(NormalizedRect.self, forKey: .additionalSubtitleLayoutRect) ?? .defaultAdditionalBannerArea
        overlayEditMode = try container.decodeIfPresent(OverlayEditMode.self, forKey: .overlayEditMode) ?? .videoPosition
        favoriteFontNames = try container.decodeIfPresent([String].self, forKey: .favoriteFontNames) ?? []
        overlayPresets = try container.decodeIfPresent([OverlayPreset].self, forKey: .overlayPresets) ?? []
        currentOverlayPath = try container.decodeIfPresent(String.self, forKey: .currentOverlayPath)
    }
}
