import AVFoundation
import CoreVideo

/// Video to MP4, MOV or M4V with H.264, HEVC or ProRes through VideoToolbox (hardware on every
/// Apple silicon Mac), or a straight stream copy when the codec already fits the container.
struct VideoConverter: Converter {
    func convert(_ request: ConversionRequest, progress: @escaping ProgressHandler) async throws -> ConversionOutput {
        let options = request.settings.video
        let format = request.settings.format
        let asset = AVURLAsset(url: request.source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw ConversionError.noVideoTrack }
        let audioTrack = options.includeAudio ? try await asset.loadTracks(withMediaType: .audio).first : nil
        let fullDuration = try await asset.load(.duration).seconds
        let trim = request.settings.trim
        let start = trim?.start ?? 0
        let duration = request.settings.outputDuration(source: fullDuration) ?? fullDuration
        let (naturalSize, transform, nominalRate, videoFormats) = try await videoTrack.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)
        let fileType: AVFileType = switch format {
        case .mov: .mov
        case .m4v: .m4v
        default: .mp4
        }

        var codec = format.videoCodecs.contains(options.codec) ? options.codec : .h264
        let sourceCodec = videoFormats.first.map(CMFormatDescriptionGetMediaSubType)
        if codec == .passthrough, !Self.container(fileType, accepts: sourceCodec) { codec = .h264 }

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: request.destination, fileType: fileType)
        writer.shouldOptimizeForNetworkUse = fileType != .mov

        // Video track
        let videoOutput: AVAssetReaderTrackOutput
        let videoInput: AVAssetWriterInput
        var frameInterval = 0.0
        if codec == .passthrough {
            videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormats.first)
        } else {
            let size = Self.targetSize(natural: naturalSize, resolution: options.resolution)
            let sourceRate = Double(nominalRate > 0 ? nominalRate : 30)
            let rate = options.frameRate == .original ? sourceRate : min(Double(options.frameRate.rawValue), sourceRate)
            if rate < sourceRate - 0.01 { frameInterval = 1 / rate }
            let pixelFormat = codec == .proRes4444 ? kCVPixelFormatType_32BGRA : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat])
            let target = options.targetVideoBitrate(duration: duration, audioBitsPerSecond: 192_000)
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: Self.videoSettings(codec: codec, size: size, frameRate: rate,
                                                                                                    quality: options.quality, bitrate: target))
        }
        videoOutput.alwaysCopiesSampleData = false
        videoInput.transform = transform
        videoInput.expectsMediaDataInRealTime = false
        guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else {
            throw ConversionError.encoderUnavailable(codec.displayName)
        }
        reader.add(videoOutput)
        writer.add(videoInput)

        // Audio track: copied when the container accepts it as is, AAC otherwise.
        var audio: (output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)?
        if let audioTrack {
            let audioFormat = try await audioTrack.load(.formatDescriptions).first
            let copy = codec == .passthrough && Self.container(fileType, acceptsAudio: audioFormat.map(CMFormatDescriptionGetMediaSubType))
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: copy ? nil : Self.decodedAudioSettings)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: copy ? nil : Self.aacSettings, sourceFormatHint: copy ? audioFormat : nil)
            output.alwaysCopiesSampleData = false
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audio = (output, input)
            }
        }

        if let trim {
            reader.timeRange = CMTimeRange(start: CMTime(seconds: trim.start, preferredTimescale: 600),
                                           duration: CMTime(seconds: trim.duration, preferredTimescale: 600))
        }
        guard reader.startReading() else { throw reader.error ?? ConversionError.unreadable }
        guard writer.startWriting() else { throw writer.error ?? ConversionError.failed("The video couldn’t be written.") }
        writer.startSession(atSourceTime: CMTime(seconds: start, preferredTimescale: 600))

        let throttle = ProgressThrottle(progress)
        do {
            try await Self.pump(video: (videoOutput, videoInput), audio: audio, frameInterval: frameInterval, writer: writer) { seconds in
                if duration > 0 { throttle.report((seconds - start) / duration * 0.99) }
            }
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? ConversionError.unreadable
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? ConversionError.failed("The video couldn’t be finished.")
        }
        throttle.report(1)
        return .file
    }

    /// Feeds both tracks from one loop so neither starves the writer's interleaving.
    private static func pump(
        video: (AVAssetReaderTrackOutput, AVAssetWriterInput),
        audio: (output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)?,
        frameInterval: Double,
        writer: AVAssetWriter,
        progress: (Double) -> Void
    ) async throws {
        var videoDone = false
        var audioDone = audio == nil
        var nextFrameTime = -Double.infinity

        while !(videoDone && audioDone) {
            try Task.checkCancellation()
            var moved = false

            if !videoDone, video.1.isReadyForMoreMediaData {
                moved = true
                if let sample = video.0.copyNextSampleBuffer() {
                    let time = sample.presentationTimeStamp.seconds
                    // Dropping frames lowers the frame rate; keep each one that reaches the next slot.
                    if frameInterval == 0 || time >= nextFrameTime - frameInterval * 0.25 {
                        nextFrameTime = max(nextFrameTime + frameInterval, time + frameInterval * 0.5)
                        guard video.1.append(sample) else { throw writer.error ?? ConversionError.failed("A video frame couldn’t be written.") }
                    }
                    if time.isFinite { progress(time) }
                } else {
                    video.1.markAsFinished()
                    videoDone = true
                }
            }

            if !audioDone, let audio, audio.input.isReadyForMoreMediaData {
                moved = true
                if let sample = audio.output.copyNextSampleBuffer() {
                    guard audio.input.append(sample) else { throw writer.error ?? ConversionError.failed("Audio couldn’t be written.") }
                } else {
                    audio.input.markAsFinished()
                    audioDone = true
                }
            }

            if writer.status == .failed { throw writer.error ?? ConversionError.failed("The video couldn’t be written.") }
            if !moved { try await Task.sleep(for: .milliseconds(2)) }
        }
    }

    /// The encoded size: the shorter side limited by `resolution`, never upscaled, even numbers.
    /// Works in the track's stored orientation; the writer's transform rotates it on playback.
    static func targetSize(natural: CGSize, resolution: Resolution) -> CGSize {
        let width = abs(natural.width), height = abs(natural.height)
        let shorter = min(width, height)
        let scale = resolution == .original || shorter <= CGFloat(resolution.rawValue) ? 1 : CGFloat(resolution.rawValue) / shorter
        func even(_ value: CGFloat) -> CGFloat { max(2, (value * scale / 2).rounded() * 2) }
        return CGSize(width: even(width), height: even(height))
    }

    static func videoSettings(codec: VideoCodec, size: CGSize, frameRate: Double, quality: Quality, bitrate target: Double? = nil) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
        ]
        switch codec {
        case .h264, .hevc:
            let efficiency = codec == .hevc ? 0.6 : 1.0
            let bitrate = target ?? max(400_000, size.width * size.height * frameRate * quality.bitsPerPixel * efficiency)
            settings[AVVideoCodecKey] = codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264
            var compression: [String: Any] = [
                AVVideoAverageBitRateKey: Int(bitrate),
                AVVideoExpectedSourceFrameRateKey: Int(frameRate.rounded()),
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
                AVVideoAllowFrameReorderingKey: true,
            ]
            if codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
            settings[AVVideoCompressionPropertiesKey] = compression
        case .proRes422:
            settings[AVVideoCodecKey] = AVVideoCodecType.proRes422
        case .proRes4444:
            settings[AVVideoCodecKey] = AVVideoCodecType.proRes4444
        case .passthrough:
            break
        }
        return settings
    }

    static var decodedAudioSettings: [String: Any] { [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsNonInterleaved: false,
        AVLinearPCMIsBigEndianKey: false,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
    ] }

    static var aacSettings: [String: Any] { [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 192_000,
    ] }

    static func container(_ type: AVFileType, accepts codec: FourCharCode?) -> Bool {
        guard let codec else { return false }
        if type == .mov { return true }
        return [kCMVideoCodecType_H264, kCMVideoCodecType_HEVC, kCMVideoCodecType_MPEG4Video, kCMVideoCodecType_AV1].contains(codec)
    }

    static func container(_ type: AVFileType, acceptsAudio codec: FourCharCode?) -> Bool {
        guard let codec else { return false }
        if type == .mov { return true }
        return [kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2, kAudioFormatAppleLossless,
                kAudioFormatAC3, kAudioFormatEnhancedAC3].contains(codec)
    }
}
