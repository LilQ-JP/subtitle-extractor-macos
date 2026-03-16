import Foundation
import UniformTypeIdentifiers

enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case japanese = "ja"
    case english = "en"
    case chinese = "zh"
    case korean = "ko"

    static let defaultsKey = "CaptionStudio.appLanguage"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .japanese:
            return "日本語"
        case .english:
            return "English"
        case .chinese:
            return "中文"
        case .korean:
            return "한국어"
        }
    }

    func pick(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        switch self {
        case .japanese:
            return japanese
        case .english:
            return english
        case .chinese:
            return chinese
        case .korean:
            return korean
        }
    }

    init(storedRawValue: String?) {
        self = AppLanguage(rawValue: storedRawValue ?? "") ?? .japanese
    }
}

enum CaptionStylePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case classic
    case youtube
    case systemAccessibility

    var id: String { rawValue }

    func displayName(in appLanguage: AppLanguage) -> String {
        switch self {
        case .classic:
            return appLanguage.pick("クラシック", "Classic", "经典", "클래식")
        case .youtube:
            return "YouTube"
        case .systemAccessibility:
            return "macOS"
        }
    }
}

enum WorkspaceLayoutPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case balanced
    case viewerFocus
    case editorFocus

    var id: String { rawValue }

    func displayName(in appLanguage: AppLanguage) -> String {
        switch self {
        case .balanced:
            return appLanguage.pick("バランス", "Balanced", "平衡", "균형")
        case .viewerFocus:
            return appLanguage.pick("プレビュー重視", "Viewer Focus", "预览优先", "뷰어 우선")
        case .editorFocus:
            return appLanguage.pick("編集重視", "Editor Focus", "编辑优先", "편집 우선")
        }
    }

    func description(in appLanguage: AppLanguage) -> String {
        switch self {
        case .balanced:
            return appLanguage.pick(
                "プレビュー、字幕一覧、設定を均等に見たい時の標準レイアウトです。",
                "The default layout with a balanced viewer, subtitle list, and inspector.",
                "适合同时查看预览、字幕列表和设置的标准布局。",
                "뷰어, 자막 목록, 설정을 균형 있게 보는 기본 레이아웃입니다."
            )
        case .viewerFocus:
            return appLanguage.pick(
                "プレビューを大きく保ちつつ、下段で字幕一覧を確認する構成です。",
                "Keeps the viewer large and moves the subtitle work area to the bottom.",
                "让预览保持更大，下方集中处理字幕。",
                "뷰어를 크게 유지하고 아래쪽에서 자막 작업을 하는 구성입니다."
            )
        case .editorFocus:
            return appLanguage.pick(
                "プレビュー、字幕、設定を横並びで見比べながら編集する構成です。",
                "Places viewer, subtitles, and inspector side by side for editing.",
                "将预览、字幕和设置并排，方便边看边改。",
                "뷰어, 자막, 설정을 나란히 두고 비교하며 편집하는 구성입니다."
            )
        }
    }
}

enum WrapTimingMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case early
    case balanced
    case late

    var id: String { rawValue }

    func displayName(in appLanguage: AppLanguage) -> String {
        switch self {
        case .early:
            return appLanguage.pick("早め", "Early", "偏早", "빠르게")
        case .balanced:
            return appLanguage.pick("標準", "Balanced", "标准", "표준")
        case .late:
            return appLanguage.pick("遅め", "Late", "偏晚", "늦게")
        }
    }

    func shortDescription(in appLanguage: AppLanguage) -> String {
        switch self {
        case .early:
            return appLanguage.pick("短めの行で切ります。", "Break into shorter lines.", "会更早换行。", "더 짧은 줄에서 끊습니다.")
        case .balanced:
            return appLanguage.pick("読みやすさ重視の標準です。", "A balanced default for readability.", "以可读性为主的标准设置。", "읽기 쉬운 기본 설정입니다.")
        case .late:
            return appLanguage.pick("できるだけ長めの行を保ちます。", "Keep each line longer before wrapping.", "尽量保持更长的一行。", "가능하면 한 줄을 길게 유지합니다.")
        }
    }

    var fillRatio: Double {
        switch self {
        case .early:
            return 0.74
        case .balanced:
            return 0.86
        case .late:
            return 0.96
        }
    }
}

enum OCRRefinementMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off
    case smart
    case aggressive

    var id: String { rawValue }

    func displayName(in appLanguage: AppLanguage) -> String {
        switch self {
        case .off:
            return appLanguage.pick("オフ", "Off", "关闭", "끔")
        case .smart:
            return appLanguage.pick("自動", "Auto", "自动", "자동")
        case .aggressive:
            return appLanguage.pick("高精度", "High Precision", "高精度", "고정밀")
        }
    }

    func shortDescription(in appLanguage: AppLanguage) -> String {
        switch self {
        case .off:
            return appLanguage.pick(
                "AI の読み直しを使わず、まず速さを優先します。",
                "Skips AI rereading and prioritizes speed.",
                "不使用 AI 复读，优先速度。",
                "AI 재판독을 건너뛰고 속도를 우선합니다."
            )
        case .smart:
            return appLanguage.pick(
                "怪しい字幕だけ AI で読み直すので、速さと精度のバランスが良い設定です。",
                "Only suspicious subtitles are reread with AI, balancing speed and accuracy.",
                "只对可疑字幕使用 AI 复读，兼顾速度和精度。",
                "의심스러운 자막만 AI로 다시 읽어 속도와 정확도의 균형이 좋습니다."
            )
        case .aggressive:
            return appLanguage.pick(
                "多くの字幕を AI で読み直して精度を優先しますが、時間がかかります。",
                "Rereads many subtitles with AI for maximum accuracy, but it is slower.",
                "会对更多字幕执行 AI 复读以优先精度，但会更慢。",
                "더 많은 자막을 AI로 다시 읽어 정확도를 우선하지만 느립니다."
            )
        }
    }
}

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

    func displayName(in appLanguage: AppLanguage) -> String {
        switch self {
        case .original:
            return appLanguage.pick("原文", "Original", "原文", "원문")
        case .translated:
            return appLanguage.pick("翻訳字幕", "Translated", "译文字幕", "번역 자막")
        }
    }
}

enum OverlayEditMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case videoPosition
    case videoWindow
    case subtitleWindow
    case additionalSubtitleWindow

    var id: String { rawValue }

    func displayName(in appLanguage: AppLanguage) -> String {
        switch self {
        case .videoPosition:
            return appLanguage.pick("動画位置", "Video Position", "视频位置", "영상 위치")
        case .videoWindow:
            return appLanguage.pick("動画窓", "Video Window", "视频窗口", "영상 창")
        case .subtitleWindow:
            return appLanguage.pick("字幕枠", "Subtitle Frame", "字幕框", "자막 프레임")
        case .additionalSubtitleWindow:
            return appLanguage.pick("追加字幕", "Extra Caption", "附加字幕", "추가 자막")
        }
    }

    func instruction(in appLanguage: AppLanguage) -> String {
        switch self {
        case .videoPosition:
            return appLanguage.pick(
                "透明窓の上をドラッグして動画を移動します。ズームは右のスライダで調整します。",
                "Drag inside the transparent area to move the video. Use the zoom slider on the right.",
                "在透明窗口中拖动以移动视频，缩放可在右侧滑杆调整。",
                "투명 창 안에서 드래그해 영상을 옮기고, 확대는 오른쪽 슬라이더에서 조절합니다."
            )
        case .videoWindow:
            return appLanguage.pick(
                "ステージ上をドラッグして、動画をはめる窓を描き直します。",
                "Drag on the stage to redraw the video window.",
                "在舞台上拖动以重新描绘视频窗口。",
                "스테이지에서 드래그해 영상 창을 다시 그립니다."
            )
        case .subtitleWindow:
            return appLanguage.pick(
                "ステージ上をドラッグして、字幕を収める枠を描き直します。",
                "Drag on the stage to redraw the subtitle frame.",
                "在舞台上拖动以重新绘制字幕框。",
                "스테이지에서 드래그해 자막 프레임을 다시 그립니다."
            )
        case .additionalSubtitleWindow:
            return appLanguage.pick(
                "ステージ上をドラッグして、追加字幕の帯を表示する位置と大きさを決めます。",
                "Drag on the stage to place and size the extra caption banner.",
                "在舞台上拖动以决定附加字幕条的位置和大小。",
                "스테이지에서 드래그해 추가 자막 배너의 위치와 크기를 정합니다."
            )
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
    var ocrRefinementMode: OCRRefinementMode = .smart
    var detectScroll: Bool = true
    var minDuration: Double = 0.5
    var maxDuration: Double = 10.0
    var subtitleLanguage: String = "ja"
    var wrapWidthRatio: Double = 0.68
    var wrapTimingMode: WrapTimingMode = .balanced
    var preferredLineCount: Int = 0
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

struct RGBAColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let white = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    static let black = RGBAColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    static let clear = RGBAColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
}

struct CaptionVisualStyle: Hashable, Sendable {
    var textColor: RGBAColor
    var outlineColor: RGBAColor
    var backgroundColor: RGBAColor
    var shadowColor: RGBAColor
    var usesBackground: Bool
    var usesOutline: Bool
    var usesShadow: Bool
    var backgroundCornerRadius: Double
    var relativeScale: Double

    static let classic = CaptionVisualStyle(
        textColor: .white,
        outlineColor: .black,
        backgroundColor: .clear,
        shadowColor: .clear,
        usesBackground: false,
        usesOutline: true,
        usesShadow: false,
        backgroundCornerRadius: 14.0,
        relativeScale: 1.0
    )

    static let youtube = CaptionVisualStyle(
        textColor: .white,
        outlineColor: RGBAColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.72),
        backgroundColor: RGBAColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.68),
        shadowColor: RGBAColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.24),
        usesBackground: true,
        usesOutline: false,
        usesShadow: true,
        backgroundCornerRadius: 10.0,
        relativeScale: 0.96
    )
}

enum TranslationLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case japanese = "ja"
    case english = "en"
    case chinese = "zh"
    case korean = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .japanese:
            return "日本語"
        case .english:
            return "英語"
        case .chinese:
            return "中国語"
        case .korean:
            return "韓国語"
        }
    }

    func displayName(in appLanguage: AppLanguage) -> String {
        switch self {
        case .japanese:
            return appLanguage.pick("日本語", "Japanese", "日语", "일본어")
        case .english:
            return appLanguage.pick("英語", "English", "英语", "영어")
        case .chinese:
            return appLanguage.pick("中国語", "Chinese", "中文", "중국어")
        case .korean:
            return appLanguage.pick("韓国語", "Korean", "韩语", "한국어")
        }
    }
}

enum OllamaModelPurpose: String, Codable, Hashable, Sendable {
    case translation
    case visionOCR
}

struct OllamaModelRecommendation: Identifiable, Hashable, Sendable {
    let modelName: String
    let purpose: OllamaModelPurpose
    let focusLanguage: TranslationLanguage?

    var id: String {
        "\(modelName)|\(purpose.rawValue)|\(focusLanguage?.rawValue ?? "any")"
    }

    func title(in appLanguage: AppLanguage) -> String {
        switch purpose {
        case .translation:
            switch focusLanguage {
            case .korean:
                return appLanguage.pick("韓国語の会話向け", "Best for Korean dialogue", "适合韩语对白", "한국어 대사 추천")
            case .chinese:
                return appLanguage.pick("中国語の翻訳向け", "Best for Chinese translation", "适合中文翻译", "중국어 번역 추천")
            case .english:
                return appLanguage.pick("英語の自然さ重視", "Best for natural English", "适合自然英文", "영어 자연스러움 추천")
            case .japanese:
                return appLanguage.pick("日本語からの多言語向け", "Best for Japanese to multilingual", "适合日语转多语言", "일본어 기반 다국어 추천")
            case nil:
                return appLanguage.pick("汎用翻訳", "General translation", "通用翻译", "범용 번역")
            }
        case .visionOCR:
            return appLanguage.pick("AI再認識向け", "Best for AI rerecognition", "适合 AI 重新识别", "AI 재인식 추천")
        }
    }

    func detail(in appLanguage: AppLanguage) -> String {
        switch modelName {
        case "exaone3.5:7.8b":
            return appLanguage.pick(
                "韓国語と英語の言い回しに強いので、韓国語の会話やスラングに向いています。",
                "Strong at Korean and English phrasing, so it fits Korean dialogue and slang well.",
                "对韩语和英语表达很强，适合韩语对白和俚语。",
                "한국어와 영어 표현에 강해서 한국어 대사와 슬랭에 잘 맞습니다."
            )
        case "qwen2.5":
            return appLanguage.pick(
                "中国語を含む多言語に強く、文章のつながりも安定しています。",
                "Strong across multilingual tasks, especially Chinese, with stable context handling.",
                "多语言能力强，尤其适合中文，处理上下文也稳定。",
                "다국어에 강하고 특히 중국어에 강하며 문맥 처리도 안정적입니다."
            )
        case "translategemma":
            return appLanguage.pick(
                "翻訳専用の Gemma 系モデルです。幅広い言語の翻訳精度を上げたい時に向いています。",
                "A Gemma-based model built specifically for translation. Good when you want stronger translation quality across many languages.",
                "这是专门为翻译打造的 Gemma 系模型，适合提升多语言翻译质量。",
                "번역 전용 Gemma 계열 모델이라 여러 언어의 번역 품질을 높이고 싶을 때 잘 맞습니다."
            )
        case "qwen2.5vl":
            return appLanguage.pick(
                "字幕画像を直接読ませる AI 再認識向けです。韓国語や中国語の読み直しに向いています。",
                "Best for AI image rerecognition. Useful when rereading Korean or Chinese subtitle crops.",
                "适合直接读取字幕截图的 AI 重新识别，尤其适合韩语和中文。",
                "자막 이미지를 직접 읽는 AI 재인식에 적합합니다. 한국어와 중국어 재판독에 좋습니다."
            )
        default:
            return appLanguage.pick(
                "軽めで扱いやすく、翻訳と AI 再認識の両方に使いやすいモデルです。",
                "A lighter model that's easy to use for both translation and AI rerecognition.",
                "比较轻量，适合翻译和 AI 重新识别两种用途。",
                "가벼운 편이라 번역과 AI 재인식 양쪽에 쓰기 좋습니다."
            )
        }
    }
}

enum DictionaryLanguageScope: String, CaseIterable, Identifiable, Codable, Sendable {
    case any
    case japanese = "ja"
    case english = "en"
    case chinese = "zh"
    case korean = "ko"

    var id: String { rawValue }

    init(language: TranslationLanguage) {
        switch language {
        case .japanese:
            self = .japanese
        case .english:
            self = .english
        case .chinese:
            self = .chinese
        case .korean:
            self = .korean
        }
    }

    func matches(_ language: TranslationLanguage) -> Bool {
        switch self {
        case .any:
            return true
        case .japanese:
            return language == .japanese
        case .english:
            return language == .english
        case .chinese:
            return language == .chinese
        case .korean:
            return language == .korean
        }
    }

    func displayName(in appLanguage: AppLanguage) -> String {
        switch self {
        case .any:
            return appLanguage.pick("すべて", "Any", "全部", "모든 언어")
        case .japanese:
            return TranslationLanguage.japanese.displayName(in: appLanguage)
        case .english:
            return TranslationLanguage.english.displayName(in: appLanguage)
        case .chinese:
            return TranslationLanguage.chinese.displayName(in: appLanguage)
        case .korean:
            return TranslationLanguage.korean.displayName(in: appLanguage)
        }
    }
}

struct DictionaryEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var source: String = ""
    var target: String = ""
    var sourceLanguageScope: DictionaryLanguageScope = .any
    var targetLanguageScope: DictionaryLanguageScope = .any
    var isEnabledForCurrentVideo: Bool = true

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case target
        case sourceLanguageScope
        case targetLanguageScope
        case isEnabledForCurrentVideo
    }

    var isComplete: Bool {
        !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var serialized: String? {
        serialized(
            forSourceLanguage: nil,
            targetLanguage: nil,
            useForCurrentVideo: true
        )
    }

    func matches(
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage,
        useForCurrentVideo: Bool
    ) -> Bool {
        isComplete &&
            (isEnabledForCurrentVideo || !useForCurrentVideo) &&
            sourceLanguageScope.matches(sourceLanguage) &&
            targetLanguageScope.matches(targetLanguage)
    }

    func serialized(
        forSourceLanguage sourceLanguage: TranslationLanguage?,
        targetLanguage: TranslationLanguage?,
        useForCurrentVideo: Bool
    ) -> String? {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSource.isEmpty, !normalizedTarget.isEmpty else {
            return nil
        }
        if let sourceLanguage, let targetLanguage,
           !matches(
               sourceLanguage: sourceLanguage,
               targetLanguage: targetLanguage,
               useForCurrentVideo: useForCurrentVideo
           ) {
            return nil
        }
        return "\(normalizedSource)=\(normalizedTarget)"
    }

    init(
        id: UUID = UUID(),
        source: String = "",
        target: String = "",
        sourceLanguageScope: DictionaryLanguageScope = .any,
        targetLanguageScope: DictionaryLanguageScope = .any,
        isEnabledForCurrentVideo: Bool = true
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.sourceLanguageScope = sourceLanguageScope
        self.targetLanguageScope = targetLanguageScope
        self.isEnabledForCurrentVideo = isEnabledForCurrentVideo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        target = try container.decodeIfPresent(String.self, forKey: .target) ?? ""
        sourceLanguageScope = try container.decodeIfPresent(DictionaryLanguageScope.self, forKey: .sourceLanguageScope) ?? .any
        targetLanguageScope = try container.decodeIfPresent(DictionaryLanguageScope.self, forKey: .targetLanguageScope) ?? .any
        isEnabledForCurrentVideo = try container.decodeIfPresent(Bool.self, forKey: .isEnabledForCurrentVideo) ?? true
    }
}

struct TranslationPreferences: Codable, Hashable, Sendable {
    var model: String = "gemma3:4b"
    var customDictionary: String = ""
    var sourceLanguage: String = "ja"
    var targetLanguage: String = "en"
    var useContextualTranslation: Bool = true
    var contextWindow: Int = 2
    var preserveSlangAndTone: Bool = true
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

struct BackendSingleTextPayload: Codable, Sendable {
    var text: String
}

struct BackendVisionOCRPayload: Codable, Sendable {
    var images: [String]
    var sourceLanguage: String
    var hintText: String

    enum CodingKeys: String, CodingKey {
        case images
        case sourceLanguage = "source_language"
        case hintText = "hint_text"
    }
}

struct BackendRuntimeReport: Codable, Sendable {
    var python: String
    var missingModules: [String]
    var optionalMissingModules: [String] = []

    enum CodingKeys: String, CodingKey {
        case python
        case missingModules
        case optionalMissingModules
    }

    init(python: String, missingModules: [String], optionalMissingModules: [String] = []) {
        self.python = python
        self.missingModules = missingModules
        self.optionalMissingModules = optionalMissingModules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        python = try container.decode(String.self, forKey: .python)
        missingModules = try container.decode([String].self, forKey: .missingModules)
        optionalMissingModules = try container.decodeIfPresent([String].self, forKey: .optionalMissingModules) ?? []
    }

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

struct TranslationProgress: Hashable, Sendable {
    var processed: Int
    var total: Int
    var currentText: String

    var fractionCompleted: Double {
        guard total > 0 else {
            return 0.0
        }
        return min(max(Double(processed) / Double(total), 0.0), 1.0)
    }
}

struct ExportProgress: Hashable, Sendable {
    var format: ExportFormat
    var fractionCompleted: Double
    var estimatedRemainingSeconds: Double?
    var elapsedSeconds: Double

    var clampedFractionCompleted: Double {
        min(max(fractionCompleted, 0.0), 1.0)
    }
}

struct BackendExtractProgressPayload: Codable, Sendable {
    var event: String
    var processed: Int
    var total: Int
    var timestamp: Double
}

struct BackendTranslationProgressPayload: Codable, Sendable {
    var event: String
    var processed: Int
    var total: Int
    var currentText: String

    enum CodingKeys: String, CodingKey {
        case event
        case processed
        case total
        case currentText = "current_text"
    }
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
    var appLanguage: AppLanguage = .japanese
    var captionStylePreset: CaptionStylePreset = .classic
    var workspaceLayoutPreset: WorkspaceLayoutPreset = .balanced
    var fpsSample: Double = 2.0
    var ocrRefinementMode: OCRRefinementMode = .smart
    var detectScroll: Bool = true
    var minDuration: Double = 0.5
    var maxDuration: Double = 10.0
    var wrapWidthRatio: Double = 0.68
    var wrapTimingMode: WrapTimingMode = .balanced
    var preferredLineCount: Int = 0
    var subtitleFontSize: Double = 24.0
    var subtitleFontName: String = "Hiragino Sans"
    var subtitleOutlineWidth: Double = 4.0
    var exportTextMode: ExportTextMode = .translated
    var translationModel: String = "gemma3:4b"
    var preferredVisionModel: String = ""
    var sourceLanguage: String = "ja"
    var targetLanguage: String = "en"
    var useContextualTranslation: Bool = true
    var translationContextWindow: Int = 2
    var preserveSlangAndTone: Bool = true
    var sharePreReleaseAnalytics: Bool = false
    var includeDiagnosticsInFeedback: Bool = true
    var automaticallyChecksForUpdates: Bool = true
    var automaticallyDownloadsUpdates: Bool = false
    var includePrereleaseUpdates: Bool = false
    var updateCheckInterval: UpdateCheckInterval = .daily
    var lastUpdateCheckAt: Date?
    var dismissedUpdateVersion: String?
    var downloadedUpdateVersion: String?
    var downloadedUpdatePath: String?
    var useDictionaryForCurrentProject: Bool = true
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
        case appLanguage
        case captionStylePreset
        case workspaceLayoutPreset
        case fpsSample
        case ocrRefinementMode
        case detectScroll
        case minDuration
        case maxDuration
        case wrapWidthRatio
        case wrapTimingMode
        case preferredLineCount
        case subtitleFontSize
        case subtitleFontName
        case subtitleOutlineWidth
        case exportTextMode
        case translationModel
        case preferredVisionModel
        case sourceLanguage
        case targetLanguage
        case useContextualTranslation
        case translationContextWindow
        case preserveSlangAndTone
        case sharePreReleaseAnalytics
        case includeDiagnosticsInFeedback
        case automaticallyChecksForUpdates
        case automaticallyDownloadsUpdates
        case includePrereleaseUpdates
        case updateCheckInterval
        case lastUpdateCheckAt
        case dismissedUpdateVersion
        case downloadedUpdateVersion
        case downloadedUpdatePath
        case useDictionaryForCurrentProject
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
        appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .japanese
        captionStylePreset = try container.decodeIfPresent(CaptionStylePreset.self, forKey: .captionStylePreset) ?? .classic
        workspaceLayoutPreset = try container.decodeIfPresent(WorkspaceLayoutPreset.self, forKey: .workspaceLayoutPreset) ?? .balanced
        fpsSample = try container.decodeIfPresent(Double.self, forKey: .fpsSample) ?? 2.0
        ocrRefinementMode = try container.decodeIfPresent(OCRRefinementMode.self, forKey: .ocrRefinementMode) ?? .smart
        detectScroll = try container.decodeIfPresent(Bool.self, forKey: .detectScroll) ?? true
        minDuration = try container.decodeIfPresent(Double.self, forKey: .minDuration) ?? 0.5
        maxDuration = try container.decodeIfPresent(Double.self, forKey: .maxDuration) ?? 10.0
        wrapWidthRatio = try container.decodeIfPresent(Double.self, forKey: .wrapWidthRatio) ?? 0.68
        wrapTimingMode = try container.decodeIfPresent(WrapTimingMode.self, forKey: .wrapTimingMode) ?? .balanced
        preferredLineCount = try container.decodeIfPresent(Int.self, forKey: .preferredLineCount) ?? 0
        subtitleFontSize = try container.decodeIfPresent(Double.self, forKey: .subtitleFontSize) ?? 24.0
        subtitleFontName = try container.decodeIfPresent(String.self, forKey: .subtitleFontName) ?? "Hiragino Sans"
        subtitleOutlineWidth = try container.decodeIfPresent(Double.self, forKey: .subtitleOutlineWidth) ?? 4.0
        exportTextMode = try container.decodeIfPresent(ExportTextMode.self, forKey: .exportTextMode) ?? .translated
        translationModel = try container.decodeIfPresent(String.self, forKey: .translationModel) ?? "gemma3:4b"
        preferredVisionModel = try container.decodeIfPresent(String.self, forKey: .preferredVisionModel) ?? ""
        sourceLanguage = try container.decodeIfPresent(String.self, forKey: .sourceLanguage) ?? "ja"
        targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "en"
        useContextualTranslation = try container.decodeIfPresent(Bool.self, forKey: .useContextualTranslation) ?? true
        translationContextWindow = max(0, try container.decodeIfPresent(Int.self, forKey: .translationContextWindow) ?? 2)
        preserveSlangAndTone = try container.decodeIfPresent(Bool.self, forKey: .preserveSlangAndTone) ?? true
        sharePreReleaseAnalytics = try container.decodeIfPresent(Bool.self, forKey: .sharePreReleaseAnalytics) ?? false
        includeDiagnosticsInFeedback = try container.decodeIfPresent(Bool.self, forKey: .includeDiagnosticsInFeedback) ?? true
        automaticallyChecksForUpdates = try container.decodeIfPresent(Bool.self, forKey: .automaticallyChecksForUpdates) ?? true
        automaticallyDownloadsUpdates = try container.decodeIfPresent(Bool.self, forKey: .automaticallyDownloadsUpdates) ?? false
        includePrereleaseUpdates = try container.decodeIfPresent(Bool.self, forKey: .includePrereleaseUpdates) ?? false
        updateCheckInterval = try container.decodeIfPresent(UpdateCheckInterval.self, forKey: .updateCheckInterval) ?? .daily
        lastUpdateCheckAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheckAt)
        dismissedUpdateVersion = try container.decodeIfPresent(String.self, forKey: .dismissedUpdateVersion)
        downloadedUpdateVersion = try container.decodeIfPresent(String.self, forKey: .downloadedUpdateVersion)
        downloadedUpdatePath = try container.decodeIfPresent(String.self, forKey: .downloadedUpdatePath)
        useDictionaryForCurrentProject = try container.decodeIfPresent(Bool.self, forKey: .useDictionaryForCurrentProject) ?? true
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appLanguage, forKey: .appLanguage)
        try container.encode(captionStylePreset, forKey: .captionStylePreset)
        try container.encode(workspaceLayoutPreset, forKey: .workspaceLayoutPreset)
        try container.encode(fpsSample, forKey: .fpsSample)
        try container.encode(ocrRefinementMode, forKey: .ocrRefinementMode)
        try container.encode(detectScroll, forKey: .detectScroll)
        try container.encode(minDuration, forKey: .minDuration)
        try container.encode(maxDuration, forKey: .maxDuration)
        try container.encode(wrapWidthRatio, forKey: .wrapWidthRatio)
        try container.encode(wrapTimingMode, forKey: .wrapTimingMode)
        try container.encode(preferredLineCount, forKey: .preferredLineCount)
        try container.encode(subtitleFontSize, forKey: .subtitleFontSize)
        try container.encode(subtitleFontName, forKey: .subtitleFontName)
        try container.encode(subtitleOutlineWidth, forKey: .subtitleOutlineWidth)
        try container.encode(exportTextMode, forKey: .exportTextMode)
        try container.encode(translationModel, forKey: .translationModel)
        try container.encode(preferredVisionModel, forKey: .preferredVisionModel)
        try container.encode(sourceLanguage, forKey: .sourceLanguage)
        try container.encode(targetLanguage, forKey: .targetLanguage)
        try container.encode(useContextualTranslation, forKey: .useContextualTranslation)
        try container.encode(translationContextWindow, forKey: .translationContextWindow)
        try container.encode(preserveSlangAndTone, forKey: .preserveSlangAndTone)
        try container.encode(sharePreReleaseAnalytics, forKey: .sharePreReleaseAnalytics)
        try container.encode(includeDiagnosticsInFeedback, forKey: .includeDiagnosticsInFeedback)
        try container.encode(automaticallyChecksForUpdates, forKey: .automaticallyChecksForUpdates)
        try container.encode(automaticallyDownloadsUpdates, forKey: .automaticallyDownloadsUpdates)
        try container.encode(includePrereleaseUpdates, forKey: .includePrereleaseUpdates)
        try container.encode(updateCheckInterval, forKey: .updateCheckInterval)
        try container.encodeIfPresent(lastUpdateCheckAt, forKey: .lastUpdateCheckAt)
        try container.encodeIfPresent(dismissedUpdateVersion, forKey: .dismissedUpdateVersion)
        try container.encodeIfPresent(downloadedUpdateVersion, forKey: .downloadedUpdateVersion)
        try container.encodeIfPresent(downloadedUpdatePath, forKey: .downloadedUpdatePath)
        try container.encode(useDictionaryForCurrentProject, forKey: .useDictionaryForCurrentProject)
        try container.encode(dictionaryEntries, forKey: .dictionaryEntries)
        try container.encode(subtitleRegion, forKey: .subtitleRegion)
        try container.encode(overlayKeyColor, forKey: .overlayKeyColor)
        try container.encode(overlayTolerance, forKey: .overlayTolerance)
        try container.encode(overlaySoftness, forKey: .overlaySoftness)
        try container.encode(overlayVideoRect, forKey: .overlayVideoRect)
        try container.encode(overlayVideoOffset, forKey: .overlayVideoOffset)
        try container.encode(overlayVideoZoom, forKey: .overlayVideoZoom)
        try container.encode(subtitleLayoutRect, forKey: .subtitleLayoutRect)
        try container.encode(additionalSubtitleLayoutRect, forKey: .additionalSubtitleLayoutRect)
        try container.encode(overlayEditMode, forKey: .overlayEditMode)
        try container.encode(favoriteFontNames, forKey: .favoriteFontNames)
        try container.encode(overlayPresets, forKey: .overlayPresets)
        try container.encodeIfPresent(currentOverlayPath, forKey: .currentOverlayPath)
    }
}
