import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum ProductConstants {
    static let projectFileExtension = "subtitleproject"
    static let appSupportFolderName = "CaptionStudio"
    static let autosaveFilename = "Autosave.subtitleproject"
    static let persistentStateFilename = "PersistentState.json"
    static let stableReleaseAPIURL = URL(string: "https://api.github.com/repos/LilQ-JP/subtitle-extractor-macos/releases/latest")!
    static let releasesAPIURL = URL(string: "https://api.github.com/repos/LilQ-JP/subtitle-extractor-macos/releases")!
    static let releasesPageURL = URL(string: "https://github.com/LilQ-JP/subtitle-extractor-macos/releases")!
}

enum AppSupportStore {
    private static let overrideEnvironmentKey = "CAPTIONSTUDIO_APP_SUPPORT_DIR_OVERRIDE"

    static func directoryURL() -> URL {
        let folderURL: URL
        if let overridePath = ProcessInfo.processInfo.environment[overrideEnvironmentKey],
           !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            folderURL = URL(fileURLWithPath: overridePath, isDirectory: true)
        } else {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            folderURL = baseURL.appendingPathComponent(ProductConstants.appSupportFolderName, isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        return folderURL
    }
}

struct SubtitleUndoSnapshot: Sendable {
    var subtitles: [SubtitleItem]
    var selectedSubtitleID: UUID?
    var selectedSubtitleIDs: Set<UUID>
}

struct CanvasLayoutUndoSnapshot: Sendable, Equatable {
    var overlayVideoRect: NormalizedRect
    var overlayVideoOffset: SavedSize
    var overlayVideoZoom: Double
    var subtitleLayoutRect: NormalizedRect
    var additionalSubtitleLayoutRect: NormalizedRect
    var overlayEditMode: OverlayEditMode
    var overlayVideoRectIsManual: Bool
}

struct SubtitleProjectDocument: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var savedAt: Date
    var videoPath: String?
    var subtitles: [SubtitleItem]
    var selectedSubtitleID: UUID?
    var selectedSubtitleIDs: [UUID]?
    var persistentState: PersistentAppState

    init(
        schemaVersion: Int = 1,
        savedAt: Date,
        videoPath: String?,
        subtitles: [SubtitleItem],
        selectedSubtitleID: UUID?,
        selectedSubtitleIDs: [UUID]?,
        persistentState: PersistentAppState
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.videoPath = videoPath
        self.subtitles = subtitles
        self.selectedSubtitleID = selectedSubtitleID
        self.selectedSubtitleIDs = selectedSubtitleIDs
        self.persistentState = persistentState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        if let decodedDate = try? container.decode(Date.self, forKey: .savedAt) {
            savedAt = decodedDate
        } else if let decodedDateString = try? container.decode(String.self, forKey: .savedAt),
                  let parsedDate = ISO8601DateFormatter().date(from: decodedDateString) {
            savedAt = parsedDate
        } else if let decodedTimestamp = try? container.decode(Double.self, forKey: .savedAt) {
            savedAt = Date(timeIntervalSince1970: decodedTimestamp)
        } else {
            savedAt = Date()
        }
        videoPath = try? container.decodeIfPresent(String.self, forKey: .videoPath)
        subtitles = try container.decodeIfPresent([SubtitleItem].self, forKey: .subtitles) ?? []
        selectedSubtitleID = try? container.decodeIfPresent(UUID.self, forKey: .selectedSubtitleID)
        selectedSubtitleIDs = try? container.decodeIfPresent([UUID].self, forKey: .selectedSubtitleIDs)
        persistentState = (try? container.decode(PersistentAppState.self, forKey: .persistentState)) ?? PersistentAppState()
    }
}

enum ProjectStoreError: LocalizedError {
    case invalidDocument

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "プロジェクトファイルを読み込めませんでした。"
        }
    }
}

enum ProjectStore {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func save(_ document: SubtitleProjectDocument, to url: URL) throws {
        let targetURL = normalizedProjectURL(for: url)
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: targetURL, options: .atomic)
    }

    static func load(from url: URL) throws -> SubtitleProjectDocument {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw ProjectStoreError.invalidDocument
        }
        return try decoder.decode(SubtitleProjectDocument.self, from: data)
    }

    static func looksLikeProjectFile(at url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == ProductConstants.projectFileExtension {
            return true
        }

        guard fileExtension.isEmpty || fileExtension == "json" else {
            return false
        }

        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return false
        }
        return looksLikeProjectData(data)
    }

    static func saveAutosave(_ document: SubtitleProjectDocument) throws {
        try save(document, to: autosaveURL())
    }

    static func loadAutosave() throws -> SubtitleProjectDocument? {
        let url = autosaveURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try load(from: url)
    }

    static func clearAutosave() throws {
        let url = autosaveURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    private static func autosaveURL() -> URL {
        AppSupportStore.directoryURL().appendingPathComponent(ProductConstants.autosaveFilename)
    }

    static func normalizedProjectURL(for url: URL) -> URL {
        if url.pathExtension.lowercased() == ProductConstants.projectFileExtension {
            return url
        }

        return url.appendingPathExtension(ProductConstants.projectFileExtension)
    }

    private static func looksLikeProjectData(_ data: Data) -> Bool {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let dictionary = jsonObject as? [String: Any] else {
            return false
        }

        let hasSubtitleArray = dictionary["subtitles"] is [Any]
        let hasPersistentState = dictionary["persistentState"] is [String: Any]
        let hasProjectMetadata = dictionary["videoPath"] != nil || dictionary["selectedSubtitleID"] != nil || dictionary["selectedSubtitleIDs"] != nil || dictionary["savedAt"] != nil
        return hasSubtitleArray && (hasPersistentState || hasProjectMetadata)
    }
}

enum PersistentStateStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func load() throws -> PersistentAppState? {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            return nil
        }
        return try decoder.decode(PersistentAppState.self, from: data)
    }

    static func save(_ state: PersistentAppState) throws {
        let url = fileURL()
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: url, options: .atomic)
    }

    static func clear() throws {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    static func fileURL() -> URL {
        AppSupportStore.directoryURL().appendingPathComponent(ProductConstants.persistentStateFilename)
    }
}

enum UpdateCheckInterval: String, CaseIterable, Identifiable, Codable, Sendable {
    case daily
    case everyThreeDays
    case weekly

    var id: String { rawValue }

    var minimumInterval: TimeInterval {
        switch self {
        case .daily:
            return 60 * 60 * 24
        case .everyThreeDays:
            return 60 * 60 * 24 * 3
        case .weekly:
            return 60 * 60 * 24 * 7
        }
    }

    func displayName(in appLanguage: AppLanguage) -> String {
        switch self {
        case .daily:
            return appLanguage.pick("毎日", "Every day", "每天", "매일")
        case .everyThreeDays:
            return appLanguage.pick("3日ごと", "Every 3 days", "每 3 天", "3일마다")
        case .weekly:
            return appLanguage.pick("毎週", "Every week", "每周", "매주")
        }
    }
}

struct AppUpdateAsset: Identifiable, Hashable, Sendable {
    var name: String
    var downloadURL: URL
    var contentType: String
    var size: Int64
    var digest: String?

    var id: String { name }

    var filenameExtension: String {
        URL(fileURLWithPath: name).pathExtension.lowercased()
    }

    var isInstallerPackage: Bool {
        filenameExtension == "pkg"
    }

    var isArchive: Bool {
        filenameExtension == "zip"
    }

    var suggestedLocalFilename: String {
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return downloadURL.lastPathComponent
    }
}

struct AppUpdateInfo: Identifiable, Hashable, Sendable {
    var id: String { version }
    var title: String
    var version: String
    var releaseNotes: String
    var publishedAt: Date?
    var releasePageURL: URL
    var assets: [AppUpdateAsset]

    var installerAsset: AppUpdateAsset? {
        assets.first(where: \.isInstallerPackage)
    }

    var archiveAsset: AppUpdateAsset? {
        assets.first(where: \.isArchive)
    }

    var preferredDownloadAsset: AppUpdateAsset? {
        installerAsset ?? archiveAsset
    }
}

enum UpdateInstallerError: LocalizedError {
    case noDownloadableAsset
    case integrityVerificationFailed

    var errorDescription: String? {
        switch self {
        case .noDownloadableAsset:
            return "このアップデートにはダウンロード可能なインストーラーが見つかりませんでした。"
        case .integrityVerificationFailed:
            return "ダウンロードしたアップデートの整合性を確認できませんでした。"
        }
    }
}

enum UpdateChecker {
    private struct SemanticVersion: Comparable {
        private enum PrereleaseIdentifier: Comparable {
            case numeric(Int)
            case text(String)

            static func < (lhs: PrereleaseIdentifier, rhs: PrereleaseIdentifier) -> Bool {
                switch (lhs, rhs) {
                case let (.numeric(leftValue), .numeric(rightValue)):
                    return leftValue < rightValue
                case let (.text(leftValue), .text(rightValue)):
                    return leftValue < rightValue
                case (.numeric, .text):
                    return true
                case (.text, .numeric):
                    return false
                }
            }
        }

        private var major: Int
        private var minor: Int
        private var patch: Int
        private var prerelease: [PrereleaseIdentifier]

        init?(_ rawValue: String) {
            let version = UpdateChecker.normalizedVersion(rawValue)
                .split(separator: "+", maxSplits: 1, omittingEmptySubsequences: true)
                .first
                .map(String.init) ?? UpdateChecker.normalizedVersion(rawValue)
            let components = version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let coreComponents = components[0].split(separator: ".").map(String.init)
            guard !coreComponents.isEmpty, coreComponents.count <= 3 else {
                return nil
            }

            var paddedCore = coreComponents
            while paddedCore.count < 3 {
                paddedCore.append("0")
            }

            guard let major = Int(paddedCore[0]),
                  let minor = Int(paddedCore[1]),
                  let patch = Int(paddedCore[2]) else {
                return nil
            }

            let prereleaseIdentifiers: [PrereleaseIdentifier]
            if components.count == 2 {
                prereleaseIdentifiers = components[1]
                    .split(separator: ".")
                    .compactMap { identifier in
                        if let numericValue = Int(identifier) {
                            return .numeric(numericValue)
                        }
                        let textValue = String(identifier).trimmingCharacters(in: .whitespacesAndNewlines)
                        return textValue.isEmpty ? nil : .text(textValue)
                    }
            } else {
                prereleaseIdentifiers = []
            }

            self.major = major
            self.minor = minor
            self.patch = patch
            prerelease = prereleaseIdentifiers
        }

        static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            if lhs.major != rhs.major {
                return lhs.major < rhs.major
            }
            if lhs.minor != rhs.minor {
                return lhs.minor < rhs.minor
            }
            if lhs.patch != rhs.patch {
                return lhs.patch < rhs.patch
            }

            switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
            case (true, true):
                return false
            case (true, false):
                return false
            case (false, true):
                return true
            case (false, false):
                for index in 0 ..< min(lhs.prerelease.count, rhs.prerelease.count) {
                    let leftIdentifier = lhs.prerelease[index]
                    let rightIdentifier = rhs.prerelease[index]
                    if leftIdentifier != rightIdentifier {
                        return leftIdentifier < rightIdentifier
                    }
                }
                return lhs.prerelease.count < rhs.prerelease.count
            }
        }
    }

    private struct GitHubRelease: Decodable {
        var tagName: String
        var name: String
        var body: String
        var htmlURL: URL
        var publishedAt: Date?
        var draft: Bool
        var prerelease: Bool
        var assets: [GitHubReleaseAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case publishedAt = "published_at"
            case draft
            case prerelease
            case assets
        }
    }

    private struct GitHubReleaseAsset: Decodable {
        var name: String
        var contentType: String
        var size: Int64
        var digest: String?
        var browserDownloadURL: URL
        var state: String

        enum CodingKeys: String, CodingKey {
            case name
            case contentType = "content_type"
            case size
            case digest
            case browserDownloadURL = "browser_download_url"
            case state
        }
    }

    static func currentVersion() -> String {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return shortVersion ?? buildNumber ?? "0.0.0"
    }

    static func checkForUpdates(currentVersion: String, includePrerelease: Bool = false) async throws -> AppUpdateInfo? {
        let endpoint = includePrerelease ? ProductConstants.releasesAPIURL : ProductConstants.stableReleaseAPIURL
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("CaptionStudio", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try updateInfo(from: data, currentVersion: currentVersion, includePrerelease: includePrerelease)
    }

    static func updateInfo(
        from data: Data,
        currentVersion: String,
        includePrerelease: Bool = false
    ) throws -> AppUpdateInfo? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let releases = try? decoder.decode([GitHubRelease].self, from: data) {
            return availableUpdate(from: releases, currentVersion: currentVersion, includePrerelease: includePrerelease)
        }

        let release = try decoder.decode(GitHubRelease.self, from: data)
        return availableUpdate(from: [release], currentVersion: currentVersion, includePrerelease: includePrerelease)
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        if let leftVersion = SemanticVersion(lhs), let rightVersion = SemanticVersion(rhs) {
            if leftVersion == rightVersion {
                return .orderedSame
            }
            return leftVersion < rightVersion ? .orderedAscending : .orderedDescending
        }

        return normalizedVersion(lhs).compare(normalizedVersion(rhs), options: .numeric)
    }

    private static func availableUpdate(
        from releases: [GitHubRelease],
        currentVersion: String,
        includePrerelease: Bool
    ) -> AppUpdateInfo? {
        let installedVersion = normalizedVersion(currentVersion)

        return releases
            .compactMap { release in
                updateCandidate(from: release, installedVersion: installedVersion, includePrerelease: includePrerelease)
            }
            .max { lhs, rhs in
                let comparison = compareVersions(lhs.version, rhs.version)
                if comparison == .orderedSame {
                    return (lhs.publishedAt ?? .distantPast) < (rhs.publishedAt ?? .distantPast)
                }
                return comparison == .orderedAscending
            }
    }

    private static func updateCandidate(
        from release: GitHubRelease,
        installedVersion: String,
        includePrerelease: Bool
    ) -> AppUpdateInfo? {
        guard !release.draft else {
            return nil
        }

        if release.prerelease && !includePrerelease {
            return nil
        }

        let latestVersion = normalizedVersion(release.tagName)
        guard compareVersions(latestVersion, installedVersion) == .orderedDescending else {
            return nil
        }

        return AppUpdateInfo(
            title: release.name.isEmpty ? "Caption Studio" : release.name,
            version: latestVersion,
            releaseNotes: release.body,
            publishedAt: release.publishedAt,
            releasePageURL: release.htmlURL,
            assets: mappedAssets(from: release.assets)
        )
    }

    private static func mappedAssets(from assets: [GitHubReleaseAsset]) -> [AppUpdateAsset] {
        assets
            .filter { $0.state == "uploaded" }
            .map {
                AppUpdateAsset(
                    name: $0.name,
                    downloadURL: $0.browserDownloadURL,
                    contentType: $0.contentType,
                    size: $0.size,
                    digest: $0.digest
                )
            }
            .sorted { lhs, rhs in
                assetPriority(lhs) < assetPriority(rhs)
            }
    }

    private static func assetPriority(_ asset: AppUpdateAsset) -> Int {
        if asset.isInstallerPackage {
            return 0
        }
        if asset.isArchive {
            return 1
        }
        return 2
    }

    static func normalizedVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }
}

enum UpdateInstaller {
    private static let updatesDirectoryOverrideEnvironmentKey = "CAPTIONSTUDIO_UPDATES_DIR_OVERRIDE"

    static func updatesDirectory() -> URL {
        let folderURL: URL
        if let overrideDirectory = getenv(updatesDirectoryOverrideEnvironmentKey).map({ String(cString: $0) }),
           !overrideDirectory.isEmpty {
            folderURL = URL(fileURLWithPath: overrideDirectory, isDirectory: true)
        } else {
            folderURL = AppSupportStore.directoryURL()
                .appendingPathComponent("Updates", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    static func storedUpdateURL(for update: AppUpdateInfo) -> URL? {
        guard let asset = update.preferredDownloadAsset else {
            return nil
        }
        let targetURL = destinationURL(for: asset, version: update.version)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return nil
        }
        return targetURL
    }

    static func downloadAndStore(
        update: AppUpdateInfo,
        progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        guard let asset = update.preferredDownloadAsset else {
            throw UpdateInstallerError.noDownloadableAsset
        }

        let destinationURL = destinationURL(for: asset, version: update.version)
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            if try verifyIfNeeded(fileAt: destinationURL, digest: asset.digest) {
                return destinationURL
            }
            try? FileManager.default.removeItem(at: destinationURL)
        }

        let downloader = UpdateDownloadSession(progressHandler: progressHandler)
        let temporaryURL = try await downloader.download(from: asset.downloadURL)

        try removeAllStoredUpdates(exceptVersion: update.version)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)

        guard try verifyIfNeeded(fileAt: destinationURL, digest: asset.digest) else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw UpdateInstallerError.integrityVerificationFailed
        }

        return destinationURL
    }

    @discardableResult
    static func openInstaller(at url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    static func removeAllStoredUpdates(exceptVersion: String? = nil) throws {
        let root = updatesDirectory()
        let contents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for entry in contents {
            if entry.lastPathComponent == exceptVersion {
                continue
            }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private static func destinationURL(for asset: AppUpdateAsset, version: String) -> URL {
        updatesDirectory()
            .appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent(asset.suggestedLocalFilename)
    }

    private static func verifyIfNeeded(fileAt url: URL, digest: String?) throws -> Bool {
        guard let digest, digest.lowercased().hasPrefix("sha256:") else {
            return true
        }

        let expectedHex = String(digest.dropFirst("sha256:".count)).lowercased()
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let actualHex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return actualHex == expectedHex
    }
}

private final class UpdateDownloadSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progressHandler: @Sendable (Double) -> Void
    private var session: URLSession?
    private nonisolated(unsafe) var continuation: CheckedContinuation<URL, Error>?
    private nonisolated(unsafe) var hasFinished = false

    init(progressHandler: @escaping @Sendable (Double) -> Void) {
        self.progressHandler = progressHandler
        super.init()
    }

    deinit {
        session?.invalidateAndCancel()
    }

    func download(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            hasFinished = false
            self.continuation = continuation
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            return
        }

        let fraction = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0.0), 1.0)
        progressHandler(fraction)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let preservedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(location.pathExtension.isEmpty ? "download" : location.pathExtension)

        do {
            if FileManager.default.fileExists(atPath: preservedURL.path) {
                try FileManager.default.removeItem(at: preservedURL)
            }
            try FileManager.default.moveItem(at: location, to: preservedURL)
            finish(with: .success(preservedURL))
        } catch {
            finish(with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(with: .failure(error))
        }
    }

    private func finish(with result: Result<URL, Error>) {
        guard !hasFinished else {
            return
        }
        hasFinished = true
        session?.finishTasksAndInvalidate()
        session = nil

        switch result {
        case .success(let url):
            continuation?.resume(returning: url)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

extension UTType {
    static var subtitleProject: UTType {
        UTType(filenameExtension: ProductConstants.projectFileExtension, conformingTo: .json) ?? .json
    }
}
