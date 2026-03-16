import AppKit
import Foundation

enum FeedbackCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case bug
    case ocr
    case translation
    case idea

    var id: String { rawValue }

    func displayName(in appLanguage: AppLanguage) -> String {
        switch self {
        case .bug:
            return appLanguage.pick("不具合", "Bug", "问题", "버그")
        case .ocr:
            return appLanguage.pick("OCR精度", "OCR Quality", "OCR 精度", "OCR 정확도")
        case .translation:
            return appLanguage.pick("翻訳品質", "Translation Quality", "翻译质量", "번역 품질")
        case .idea:
            return appLanguage.pick("改善提案", "Idea", "改进建议", "개선 제안")
        }
    }
}

enum FeedbackLogLevel: String, Codable, Hashable, Sendable {
    case info
    case warning
    case error
}

struct FeedbackLogEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var level: FeedbackLogLevel = .info
    var message: String = ""
}

struct FeedbackDraft: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var category: FeedbackCategory = .bug
    var message: String = ""
    var includeScreenshot: Bool = true
    var includeDiagnostics: Bool = true
}

struct FeedbackReportContext: Codable, Sendable {
    var appVersion: String
    var buildNumber: String
    var appLanguage: String
    var subtitleLanguage: String
    var translationTargetLanguage: String
    var translationModel: String
    var preferredVisionModel: String
    var ollamaAvailable: Bool
    var currentVideoName: String?
    var currentProjectName: String?
    var latestStatusMessage: String
    var latestErrorMessage: String?
    var sharePreReleaseAnalytics: Bool
    var includeDiagnosticsInFeedback: Bool
    var workspaceLayout: String
    var timestamp: Date
    var osVersion: String
    var recentLogs: [FeedbackLogEntry]
}

struct FeedbackSubmissionResult: Sendable {
    var archiveURL: URL
    var mailComposerOpened: Bool
}

enum FeedbackService {
    static let recipientAddress = "contact@lilq-official.com"

    @MainActor
    static func createArchive(
        context: FeedbackReportContext,
        draft: FeedbackDraft,
        window: NSWindow?
    ) throws -> URL {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionStudioFeedback", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let reportURL = baseDirectory.appendingPathComponent("report.json")
        let reportData = try encoder.encode(context)
        try reportData.write(to: reportURL, options: .atomic)

        let summary = """
        Category: \(draft.category.rawValue)
        Timestamp: \(ISO8601DateFormatter().string(from: Date()))

        Message:
        \(draft.message.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        try summary.data(using: .utf8)?.write(
            to: baseDirectory.appendingPathComponent("feedback.txt"),
            options: .atomic
        )

        if draft.includeScreenshot,
           let pngData = screenshotPNGData(from: window)
        {
            try pngData.write(
                to: baseDirectory.appendingPathComponent("window-screenshot.png"),
                options: .atomic
            )
        }

        if draft.includeDiagnostics {
            let diagnosticsText = """
            App Version: \(context.appVersion) (\(context.buildNumber))
            App Language: \(context.appLanguage)
            Subtitle Language: \(context.subtitleLanguage)
            Translation Target: \(context.translationTargetLanguage)
            Translation Model: \(context.translationModel)
            Vision Model: \(context.preferredVisionModel)
            Ollama Available: \(context.ollamaAvailable)
            Layout: \(context.workspaceLayout)
            Current Project: \(context.currentProjectName ?? "-")
            Current Video: \(context.currentVideoName ?? "-")
            Latest Status: \(context.latestStatusMessage)
            Latest Error: \(context.latestErrorMessage ?? "-")
            macOS: \(context.osVersion)
            """
            try diagnosticsText.data(using: .utf8)?.write(
                to: baseDirectory.appendingPathComponent("diagnostics.txt"),
                options: .atomic
            )
        }

        let archiveURL = baseDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseDirectory.lastPathComponent).zip")
        try createArchive(from: baseDirectory, archiveURL: archiveURL)
        return archiveURL
    }

    @MainActor
    static func composeEmail(
        draft: FeedbackDraft,
        archiveURL: URL
    ) -> Bool {
        guard let service = NSSharingService(named: .composeEmail) else {
            return false
        }

        let subject = "[Caption Studio] \(draft.category.rawValue.capitalized) Feedback"
        let body = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)

        service.recipients = [recipientAddress]
        service.subject = subject
        service.perform(withItems: [body as NSString, archiveURL])
        return true
    }

    @MainActor
    static func revealArchive(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @MainActor
    private static func screenshotPNGData(from window: NSWindow?) -> Data? {
        let targetWindow = window ?? NSApp.keyWindow ?? NSApp.mainWindow
        guard let contentView = targetWindow?.contentView else {
            return nil
        }

        let bounds = contentView.bounds
        guard let representation = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        contentView.cacheDisplay(in: bounds, to: representation)
        return representation.representation(using: .png, properties: [:])
    }

    private static func createArchive(from directoryURL: URL, archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            directoryURL.path,
            archiveURL.path,
        ]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "SubtitleExtractor.Feedback",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "フィードバック添付ファイルの作成に失敗しました。"]
            )
        }
    }
}
