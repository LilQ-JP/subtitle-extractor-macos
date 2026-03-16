import AppKit
@preconcurrency import AVFoundation
import CoreImage
import Foundation

struct VideoRenderRequest {
    var sourceURL: URL
    var destinationURL: URL
    var format: ExportFormat
    var subtitles: [SubtitleItem]
    var textMode: ExportTextMode
    var subtitleRect: NormalizedRect
    var fontName: String
    var fontSize: CGFloat
    var outlineWidth: CGFloat
    var captionStyle: CaptionVisualStyle = .classic
    var wrapTimingMode: WrapTimingMode = .balanced
    var preferredLineCount: Int = 0
    var overlayImage: NSImage?
    var outputSize: CGSize?
    var videoRect: NormalizedRect?
    var videoOffset: CGSize = .zero
    var videoZoom: Double = 1.0
}

enum VideoBurnInError: LocalizedError {
    case invalidFormat
    case videoTrackMissing
    case exportSessionUnavailable
    case unsupportedFileType
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "動画書き出しは MP4 または MOV を選択してください。"
        case .videoTrackMissing:
            return "書き出し元の動画トラックを取得できませんでした。"
        case .exportSessionUnavailable:
            return "動画書き出しセッションを作成できませんでした。"
        case .unsupportedFileType:
            return "この動画は指定した形式で書き出せませんでした。"
        case let .exportFailed(message):
            return message
        }
    }
}

@MainActor
enum VideoBurnInExporter {
    static func export(
        _ request: VideoRenderRequest,
        progressHandler: (@MainActor @Sendable (_ fractionCompleted: Double, _ estimatedRemainingSeconds: Double?, _ elapsedSeconds: Double) -> Void)? = nil
    ) async throws {
        guard request.format == .mp4 || request.format == .mov else {
            throw VideoBurnInError.invalidFormat
        }

        let asset = AVURLAsset(url: request.sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw VideoBurnInError.videoTrackMissing
        }

        let (normalizedTransform, orientedSize) = try await normalizedVideoTransform(for: sourceVideoTrack)
        let renderSize = resolvedRenderSize(request.outputSize ?? orientedSize)
        let renderRect = CGRect(origin: .zero, size: renderSize)
        let subtitleFrame = pixelRect(for: request.subtitleRect, in: renderSize)
        let videoFrame = if let videoRect = request.videoRect {
            pixelRect(for: videoRect, in: renderSize)
        } else {
            renderRect
        }
        let overlayImage = preparedOverlayImage(request.overlayImage, renderSize: renderSize)
        let preparedSubtitles = request.subtitles.compactMap { subtitle in
            preparedSubtitle(
                from: subtitle,
                mode: request.textMode,
                frame: subtitleFrame,
                fontName: request.fontName,
                fontSize: request.fontSize,
                outlineWidth: request.outlineWidth,
                style: request.captionStyle,
                wrapTimingMode: request.wrapTimingMode,
                preferredLineCount: request.preferredLineCount
            )
        }
        let usesOverlayLayout = request.videoRect != nil

        let nominalFrameRate = try await sourceVideoTrack.load(.nominalFrameRate)
        let frameRate = nominalFrameRate > 0 ? nominalFrameRate : 30.0
        let videoComposition = AVMutableVideoComposition(asset: asset) { compositionRequest in
            let seconds = max(0.0, compositionRequest.compositionTime.seconds)
            var outputImage = renderedVideoImage(
                from: compositionRequest.sourceImage,
                normalizedTransform: normalizedTransform,
                orientedSize: orientedSize,
                renderSize: renderSize,
                targetFrame: videoFrame,
                videoOffset: request.videoOffset,
                videoZoom: usesOverlayLayout ? request.videoZoom : 1.0,
                usesOverlayLayout: usesOverlayLayout
            )

            let background = CIImage(color: .black).cropped(to: renderRect)
            outputImage = outputImage.composited(over: background)

            if let overlayImage {
                outputImage = overlayImage.composited(over: outputImage)
            }

            for subtitle in preparedSubtitles where subtitle.contains(time: seconds) {
                let translatedSubtitle = subtitle.image.transformed(
                    by: CGAffineTransform(translationX: subtitle.frame.minX, y: subtitle.frame.minY)
                )
                outputImage = translatedSubtitle.composited(over: outputImage)
            }

            compositionRequest.finish(with: outputImage.cropped(to: renderRect), context: nil)
        }
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: Int32(max(frameRate.rounded(), 1)))

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoBurnInError.exportSessionUnavailable
        }

        let fileType: AVFileType = request.format == .mp4 ? .mp4 : .mov
        guard exportSession.supportedFileTypes.contains(fileType) else {
            throw VideoBurnInError.unsupportedFileType
        }

        try? FileManager.default.removeItem(at: request.destinationURL)

        exportSession.outputURL = request.destinationURL
        exportSession.outputFileType = fileType
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = request.format == .mp4

        try await exportSession.exportChecked(progressHandler: progressHandler)
    }

    private static func preparedSubtitle(
        from subtitle: SubtitleItem,
        mode: ExportTextMode,
        frame: CGRect,
        fontName: String,
        fontSize: CGFloat,
        outlineWidth: CGFloat,
        style: CaptionVisualStyle,
        wrapTimingMode: WrapTimingMode,
        preferredLineCount: Int
    ) -> PreparedSubtitle? {
        let baseText = if mode == .translated && !subtitle.translated.isEmpty {
            subtitle.translated
        } else {
            subtitle.text
        }

        let fittedLayout = SubtitleUtilities.fitSubtitleLayout(
            text: baseText,
            regionSize: frame.size,
            fontName: fontName,
            preferredFontSize: fontSize,
            outlineWidth: outlineWidth,
            timingMode: wrapTimingMode,
            preferredLineCount: preferredLineCount
        )

        guard !fittedLayout.text.isEmpty,
              let subtitleImage = SubtitleUtilities.subtitleImage(
                  text: fittedLayout.text,
                  size: frame.size,
                  fontName: fontName,
                  fontSize: CGFloat(fittedLayout.fontSize),
                  outlineWidth: CGFloat(fittedLayout.outlineWidth),
                  style: style
              ) else {
            return nil
        }

        return PreparedSubtitle(
            startTime: subtitle.startTime,
            endTime: subtitle.endTime,
            frame: frame,
            image: scaledSubtitleImage(
                CIImage(cgImage: subtitleImage),
                targetSize: frame.size
            )
        )
    }

    private static func normalizedVideoTransform(for track: AVAssetTrack) async throws -> (CGAffineTransform, CGSize) {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let normalizedTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -transformedRect.minX, y: -transformedRect.minY)
        )
        let orientedSize = CGSize(
            width: abs(transformedRect.width),
            height: abs(transformedRect.height)
        )
        return (normalizedTransform, orientedSize)
    }

    nonisolated private static func renderedVideoImage(
        from sourceImage: CIImage,
        normalizedTransform: CGAffineTransform,
        orientedSize: CGSize,
        renderSize: CGSize,
        targetFrame: CGRect,
        videoOffset: CGSize,
        videoZoom: Double,
        usesOverlayLayout: Bool
    ) -> CIImage {
        let orientedImage = sourceImage.transformed(by: normalizedTransform)
        let fullRect = CGRect(origin: .zero, size: renderSize)

        let baseScale = min(
            targetFrame.width / max(orientedSize.width, 1.0),
            targetFrame.height / max(orientedSize.height, 1.0)
        )
        let scaleFactor = usesOverlayLayout
            ? baseScale * max(1.0, CGFloat(videoZoom))
            : min(
                fullRect.width / max(orientedSize.width, 1.0),
                fullRect.height / max(orientedSize.height, 1.0)
            )

        let displayedSize = CGSize(
            width: orientedSize.width * scaleFactor,
            height: orientedSize.height * scaleFactor
        )

        let offsetX = videoOffset.width * targetFrame.width * 0.5
        let offsetY = videoOffset.height * targetFrame.height * 0.5
        let originX = targetFrame.midX - displayedSize.width / 2.0 + offsetX
        let originY = targetFrame.midY - displayedSize.height / 2.0 - offsetY

        let scaled = orientedImage.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
        let translated = scaled.transformed(by: CGAffineTransform(translationX: originX, y: originY))
        return translated.cropped(to: usesOverlayLayout ? targetFrame : fullRect)
    }

    private static func pixelRect(for normalizedRect: NormalizedRect, in size: CGSize) -> CGRect {
        CGRect(
            x: CGFloat(normalizedRect.x) * size.width,
            y: size.height - CGFloat(normalizedRect.y + normalizedRect.height) * size.height,
            width: CGFloat(normalizedRect.width) * size.width,
            height: CGFloat(normalizedRect.height) * size.height
        ).integral
    }

    private static func resolvedRenderSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(2.0, ceil(size.width / 2.0) * 2.0),
            height: max(2.0, ceil(size.height / 2.0) * 2.0)
        )
    }

    private static func preparedOverlayImage(_ image: NSImage?, renderSize: CGSize) -> CIImage? {
        guard let image,
              let cgImage = SubtitleUtilities.cgImage(from: image) else {
            return nil
        }

        let overlayImage = CIImage(cgImage: cgImage)
        let scaleX = renderSize.width / max(overlayImage.extent.width, 1.0)
        let scaleY = renderSize.height / max(overlayImage.extent.height, 1.0)
        return overlayImage
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(origin: .zero, size: renderSize))
    }

    private static func scaledSubtitleImage(_ image: CIImage, targetSize: CGSize) -> CIImage {
        let scaleX = targetSize.width / max(image.extent.width, 1.0)
        let scaleY = targetSize.height / max(image.extent.height, 1.0)
        return image
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(origin: .zero, size: targetSize))
    }
}

private struct PreparedSubtitle {
    let startTime: Double
    let endTime: Double
    let frame: CGRect
    let image: CIImage

    func contains(time: Double) -> Bool {
        time >= startTime && time < endTime
    }
}

private extension AVAssetExportSession {
    func exportChecked(
        progressHandler: (@MainActor @Sendable (_ fractionCompleted: Double, _ estimatedRemainingSeconds: Double?, _ elapsedSeconds: Double) -> Void)? = nil
    ) async throws {
        let box = ExportSessionBox(session: self)
        let startedAt = Date()
        let progressTask = Task.detached(priority: .utility) { [box] in
            while !Task.isCancelled {
                let fractionCompleted = Double(box.session.progress)
                let elapsedSeconds = Date().timeIntervalSince(startedAt)
                let estimatedRemainingSeconds: Double? = if fractionCompleted > 0.01 {
                    max(0.0, elapsedSeconds * (1.0 - fractionCompleted) / fractionCompleted)
                } else {
                    nil
                }
                if let progressHandler {
                    await progressHandler(fractionCompleted, estimatedRemainingSeconds, elapsedSeconds)
                }

                switch box.session.status {
                case .waiting, .exporting:
                    try? await Task.sleep(for: .milliseconds(250))
                default:
                    return
                }
            }
        }
        defer { progressTask.cancel() }

        try await withCheckedThrowingContinuation { continuation in
            box.session.exportAsynchronously {
                switch box.session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: VideoBurnInError.exportFailed(box.session.error?.localizedDescription ?? "動画書き出しに失敗しました。"))
                case .cancelled:
                    continuation.resume(throwing: VideoBurnInError.exportFailed("動画書き出しがキャンセルされました。"))
                default:
                    continuation.resume(throwing: VideoBurnInError.exportFailed("動画書き出しが途中で終了しました。"))
                }
            }
        }

        if let progressHandler {
            let elapsedSeconds = Date().timeIntervalSince(startedAt)
            await progressHandler(1.0, 0.0, elapsedSeconds)
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(session: AVAssetExportSession) {
        self.session = session
    }
}
