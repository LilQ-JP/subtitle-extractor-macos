import Foundation

enum BackendError: LocalizedError {
    case pythonNotFound
    case resourcesMissing(String)
    case processFailed(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python 3 を見つけられませんでした。Homebrew などで Python 3 をインストールしてください。"
        case let .resourcesMissing(path):
            return "バックエンドのリソースが見つかりません: \(path)"
        case let .processFailed(message):
            return message
        case let .invalidOutput(output):
            return "バックエンドの応答を解釈できませんでした。\n\(output)"
        }
    }
}

private struct PythonInvocation: Sendable {
    var executable: String
    var prefixArguments: [String]
}

final class ExtractionProgressHandlerBox: @unchecked Sendable {
    private let handler: @MainActor (ExtractionProgress) -> Void

    init(handler: @escaping @MainActor (ExtractionProgress) -> Void) {
        self.handler = handler
    }

    func report(_ progress: ExtractionProgress) {
        Task { @MainActor in
            handler(progress)
        }
    }
}

private final class StreamLineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let lineHandler: (@Sendable (String) -> Void)?
    private var collected = ""
    private var buffer = Data()

    init(lineHandler: (@Sendable (String) -> Void)?) {
        self.lineHandler = lineHandler
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        collected.append(String(decoding: chunk, as: UTF8.self))
        buffer.append(chunk)

        while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: buffer.startIndex ..< newlineRange.lowerBound)
            buffer.removeSubrange(buffer.startIndex ... newlineRange.lowerBound)
            let line = String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }
            lineHandler?(line)
        }
    }

    func finalize() -> String {
        lock.lock()
        defer { lock.unlock() }

        if !buffer.isEmpty {
            let remainingLine = String(decoding: buffer, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainingLine.isEmpty {
                lineHandler?(remainingLine)
            }
            buffer.removeAll(keepingCapacity: false)
        }

        return collected.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PythonBackendBridge: Sendable {
    func checkEnvironment() throws -> BackendRuntimeReport {
        let script = """
import importlib.util
import json
import os
import sys

modules = ["cv2", "PIL", "requests", "meikiocr"]
missing = [name for name in modules if importlib.util.find_spec(name) is None]
print(json.dumps({"python": sys.executable, "missingModules": missing}, ensure_ascii=False))
"""
        let output = try runPython(arguments: ["-c", script], includeModulePath: false)
        return try decodeOutput(BackendRuntimeReport.self, from: output)
    }

    func extract(
        videoURL: URL,
        region: NormalizedRect?,
        preferences: ProcessingPreferences,
        progressHandler: ExtractionProgressHandlerBox? = nil
    ) async throws -> BackendExtractPayload {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let payload = try extractSync(
                        videoURL: videoURL,
                        region: region,
                        preferences: preferences,
                        progressHandler: progressHandler
                    )
                    continuation.resume(returning: payload)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func translate(
        subtitles: [SubtitleItem],
        preferences: TranslationPreferences
    ) throws -> [SubtitleItem] {
        let payload = BackendSubtitlesPayload(subtitles: subtitles)
        let input = try JSONEncoder().encode(payload)
        let output = try runBackend(
            arguments: [
                "translate",
                "--model", preferences.model,
                "--custom-dictionary", preferences.customDictionary,
                "--source-lang", preferences.sourceLanguage,
                "--target-lang", preferences.targetLanguage,
            ],
            stdin: input
        )
        let decoded = try decodeOutput(BackendSubtitlesPayload.self, from: output)
        return decoded.subtitles
    }

    func translateText(
        _ text: String,
        preferences: TranslationPreferences
    ) throws -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return ""
        }

        let translated = try translate(
            subtitles: [
                SubtitleItem(
                    index: 1,
                    startTime: 0.0,
                    endTime: 1.0,
                    text: normalized
                ),
            ],
            preferences: preferences
        )
        return translated.first?.translated.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func export(
        subtitles: [SubtitleItem],
        video: VideoMetadata?,
        destination: URL,
        processingPreferences: ProcessingPreferences,
        exportPreferences: ExportPreferences
    ) throws {
        let fallbackVideo = VideoMetadata(
            path: video?.path ?? "",
            width: video?.width ?? 1920,
            height: video?.height ?? 1080,
            fps: video?.fps ?? 30.0,
            duration: video?.duration ?? subtitles.last?.endTime ?? 0.0
        )
        let payload = BackendExtractPayload(subtitles: subtitles, video: fallbackVideo)
        let input = try JSONEncoder().encode(payload)

        _ = try runBackend(
            arguments: [
                "export",
                "--output", destination.path,
                "--format", exportPreferences.format.rawValue,
                "--translated", exportPreferences.textMode == .translated ? "true" : "false",
                "--wrap-width-ratio", String(processingPreferences.wrapWidthRatio),
                "--font-size", String(Int(processingPreferences.subtitleFontSize.rounded())),
                "--font-name", processingPreferences.subtitleFontName,
                "--outline-width", String(processingPreferences.subtitleOutlineWidth),
                "--width", String(fallbackVideo.width),
                "--height", String(fallbackVideo.height),
                "--fps", String(fallbackVideo.fps),
                "--min-duration", String(processingPreferences.minDuration),
                "--max-duration", String(processingPreferences.maxDuration),
            ],
            stdin: input
        )
    }

    private func extractSync(
        videoURL: URL,
        region: NormalizedRect?,
        preferences: ProcessingPreferences,
        progressHandler: ExtractionProgressHandlerBox? = nil
    ) throws -> BackendExtractPayload {
        var arguments = [
            "extract",
            "--video", videoURL.path,
            "--fps-sample", String(preferences.fpsSample),
            "--detect-scroll", preferences.detectScroll ? "true" : "false",
            "--min-duration", String(preferences.minDuration),
            "--max-duration", String(preferences.maxDuration),
        ]

        if let region {
            let payload = [
                "x": region.x,
                "y": region.y,
                "width": region.width,
                "height": region.height,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let json = String(decoding: data, as: UTF8.self)
            arguments.append(contentsOf: ["--region-json", json])
        }

        let output = try runBackend(
            arguments: arguments,
            stderrLineHandler: { line in
                guard let progress = parseProgress(line: line) else {
                    return
                }
                progressHandler?.report(progress)
            }
        )
        return try decodeOutput(BackendExtractPayload.self, from: output)
    }

    private func runBackend(
        arguments: [String],
        stdin: Data? = nil,
        stderrLineHandler: (@Sendable (String) -> Void)? = nil
    ) throws -> String {
        let scriptDirectory = try backendDirectory()
        let scriptURL = scriptDirectory.appendingPathComponent("backend_cli.py")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw BackendError.resourcesMissing(scriptURL.path)
        }

        return try runPython(
            arguments: [scriptURL.path] + arguments,
            stdin: stdin,
            includeModulePath: true,
            stderrLineHandler: stderrLineHandler
        )
    }

    private func runPython(
        arguments: [String],
        stdin: Data? = nil,
        includeModulePath: Bool,
        stderrLineHandler: (@Sendable (String) -> Void)? = nil
    ) throws -> String {
        let invocation = try resolvePythonInvocation()
        let backendDirectory = try backendDirectory()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.prefixArguments + arguments
        process.currentDirectoryURL = backendDirectory
        process.environment = environment(includeModulePath: includeModulePath, backendDirectory: backendDirectory)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stderrHandle = stderrPipe.fileHandleForReading
        let stderrCollector = StreamLineCollector(lineHandler: stderrLineHandler)

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            stderrCollector.append(data)
        }

        if stdin != nil {
            process.standardInput = Pipe()
        }

        try process.run()

        if let stdin,
           let stdinPipe = process.standardInput as? Pipe {
            stdinPipe.fileHandleForWriting.write(stdin)
            try? stdinPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()
        stderrHandle.readabilityHandler = nil

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrHandle.readDataToEndOfFile()
        stderrCollector.append(stderrData)
        let stderr = stderrCollector.finalize()

        let stdout = String(decoding: stdoutData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        if process.terminationStatus != 0 {
            let message = !stderr.isEmpty ? stderr : (!stdout.isEmpty ? stdout : "バックエンド処理に失敗しました。")
            throw BackendError.processFailed(message)
        }

        return stdout
    }

    private func decodeOutput<T: Decodable>(_ type: T.Type, from output: String) throws -> T {
        let decoder = JSONDecoder()
        let candidates = [output] + output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reversed()

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else {
                continue
            }
            if let decoded = try? decoder.decode(type, from: data) {
                return decoded
            }
        }

        throw BackendError.invalidOutput(output)
    }

    private func parseProgress(line: String) -> ExtractionProgress? {
        guard let data = line.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BackendExtractProgressPayload.self, from: data),
              payload.event == "extract_progress" else {
            return nil
        }

        return ExtractionProgress(
            processed: payload.processed,
            total: payload.total,
            timestamp: payload.timestamp
        )
    }

    private func environment(includeModulePath: Bool, backendDirectory: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let pathComponents = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            environment["PATH"],
        ]
            .compactMap { $0 }
            .flatMap { $0.components(separatedBy: ":") }

        environment["PATH"] = Array(NSOrderedSet(array: pathComponents)).compactMap { $0 as? String }.joined(separator: ":")

        if includeModulePath {
            let existing = environment["PYTHONPATH"].map { [$0] } ?? []
            let combined = [backendDirectory.path] + existing
            environment["PYTHONPATH"] = combined.joined(separator: ":")
        }

        return environment
    }

    private func resolvePythonInvocation() throws -> PythonInvocation {
        let environment = ProcessInfo.processInfo.environment
        let directCandidates = [
            environment["SUBTITLE_APP_PYTHON"],
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/usr/bin/python3",
        ]
            .compactMap { $0 }

        let manager = FileManager.default
        if let executable = directCandidates.first(where: { manager.isExecutableFile(atPath: $0) }) {
            return PythonInvocation(executable: executable, prefixArguments: [])
        }

        if manager.isExecutableFile(atPath: "/usr/bin/env") {
            return PythonInvocation(executable: "/usr/bin/env", prefixArguments: ["python3"])
        }

        throw BackendError.pythonNotFound
    }

    private func backendDirectory() throws -> URL {
        guard let resourceURL = Bundle.module.resourceURL else {
            throw BackendError.resourcesMissing("Bundle.module.resourceURL")
        }
        let directory = resourceURL.appendingPathComponent("Python", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw BackendError.resourcesMissing(directory.path)
        }
        return directory
    }
}
