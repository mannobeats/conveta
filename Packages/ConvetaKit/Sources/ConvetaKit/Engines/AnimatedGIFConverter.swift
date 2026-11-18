import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// A video clip to a looping animated GIF, sampled at a fixed frame rate and width.
struct AnimatedGIFConverter: Converter {
    /// GIFs past this length are huge and slow to open anywhere. People are asked to trim instead.
    static let maxFrames = 3_000

    func convert(_ request: ConversionRequest, progress: @escaping ProgressHandler) async throws -> ConversionOutput {
        let options = request.settings.animation
        let asset = AVURLAsset(url: request.source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ConversionError.noVideoTrack }
        let fullDuration = try await asset.load(.duration).seconds
        let start = request.settings.trim?.start ?? 0
        let duration = request.settings.outputDuration(source: fullDuration) ?? fullDuration
        let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
        let shown = natural.applying(transform)
        let sourceSize = CGSize(width: abs(shown.width), height: abs(shown.height))

        let fps = Double(max(1, options.framesPerSecond))
        let count = max(1, Int((duration * fps).rounded(.down)))
        guard count <= Self.maxFrames else {
            let seconds = Int(Double(Self.maxFrames) / fps)
            throw ConversionError.failed("At \(Int(fps)) fps a GIF can be at most \(seconds) seconds long. Lower the frame rate or trim the video.")
        }

        let width = Self.targetWidth(source: sourceSize.width, requested: options.width)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: width, height: (width * sourceSize.height / max(sourceSize.width, 1)).rounded())
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let destination = CGImageDestinationCreateWithURL(request.destination as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw ConversionError.encoderUnavailable("GIF")
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: options.loops ? 0 : 1],
        ] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary

        let times = (0..<count).map { CMTime(seconds: start + Double($0) / fps, preferredTimescale: 600) }
        let throttle = ProgressThrottle(progress)
        var written = 0
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            if let image = try? result.image {
                CGImageDestinationAddImage(destination, image, frameProperties)
                written += 1
            }
            throttle.report(Double(written) / Double(count) * 0.95)
        }
        guard written > 0 else { throw ConversionError.unreadable }
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.failed("The GIF couldn’t be written.") }
        throttle.report(1)
        return .file
    }

    static func targetWidth(source: CGFloat, requested: Int?) -> CGFloat {
        let limit = CGFloat(requested ?? AnimationOptions.widthCap)
        return max(16, min(source, limit, CGFloat(AnimationOptions.widthCap)).rounded())
    }
}
