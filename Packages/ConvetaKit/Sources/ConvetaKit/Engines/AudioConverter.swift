import AVFoundation
import AudioToolbox

/// Audio from any file AVFoundation reads (including the sound of a video) to
/// M4A (AAC or Apple Lossless), WAV, AIFF, FLAC or Opus, through Core Audio's encoders.
struct AudioConverter: Converter {
    func convert(_ request: ConversionRequest, progress: @escaping ProgressHandler) async throws -> ConversionOutput {
        let asset = AVURLAsset(url: request.source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw ConversionError.noAudioTrack }
        let duration = try await asset.load(.duration).seconds
        let formats = try await track.load(.formatDescriptions)
        let source = formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }

        var options = request.settings.audio
        options.bitrate = request.info.effectiveAudioBitrate(options.bitrate)
        let plan = try AudioPlan(
            format: request.settings.format,
            options: options,
            sourceRate: source?.mSampleRate ?? 48_000,
            sourceChannels: Int(source?.mChannelsPerFrame ?? 2)
        )

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: plan.readerSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ConversionError.unreadable }
        reader.add(output)

        // Opus is encoded into CAF first, then repackaged as Ogg (see OggOpusMuxer).
        let encodedURL = plan.format == .opus ? request.destination.appendingPathExtension("caf") : request.destination
        defer { if encodedURL != request.destination { try? FileManager.default.removeItem(at: encodedURL) } }
        let file = try plan.createFile(at: encodedURL)
        var disposed = false
        defer { if !disposed { ExtAudioFileDispose(file) } }

        guard reader.startReading() else { throw reader.error ?? ConversionError.unreadable }
        let throttle = ProgressThrottle(progress)
        do {
            while let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                try Self.write(sample, to: file)
                if duration > 0 { throttle.report(sample.presentationTimeStamp.seconds / duration) }
            }
        } catch {
            reader.cancelReading()
            throw error
        }
        if reader.status == .failed { throw reader.error ?? ConversionError.unreadable }

        disposed = true
        try check(ExtAudioFileDispose(file), "finish the audio file")
        if plan.format == .opus { try OggOpusMuxer.mux(caf: encodedURL, into: request.destination) }
        throttle.report(1)
        return .file
    }

    private static func write(_ sample: CMSampleBuffer, to file: ExtAudioFileRef) throws {
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0 else { return }
        var blockBuffer: CMBlockBuffer?
        var list = AudioBufferList()
        try check(CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sample, bufferListSizeNeededOut: nil, bufferListOut: &list,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        ), "read audio samples")
        try check(ExtAudioFileWrite(file, UInt32(frames), &list), "encode audio")
    }
}

/// The decisions for one audio conversion: sample rate, channels, file type and encoder format.
struct AudioPlan {
    let format: OutputFormat
    let sampleRate: Double
    let channels: Int
    let fileType: AudioFileTypeID
    let fileFormat: AudioStreamBasicDescription
    /// Encoder data rate in bit/s for AAC and Opus; `nil` for lossless formats.
    let bitrate: Int?

    init(format: OutputFormat, options: AudioOptions, sourceRate: Double, sourceChannels: Int) throws {
        self.format = format
        channels = switch options.channels {
        case .mono: 1
        case .stereo: 2
        case .original: min(max(sourceChannels, 1), 2)
        }

        var rate = options.sampleRate == .original ? sourceRate : Double(options.sampleRate.rawValue)
        let useAAC = format == .m4a && options.codec == .aac
        if useAAC { rate = min(rate, 48_000) }
        if format == .opus { rate = 48_000 }
        sampleRate = rate

        let bits = UInt32(options.bitDepth.rawValue)
        let losslessFlag = bits == 24 ? kAppleLosslessFormatFlag_24BitSourceData : kAppleLosslessFormatFlag_16BitSourceData
        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = rate
        asbd.mChannelsPerFrame = UInt32(channels)

        switch format {
        case .wav, .aiff:
            fileType = format == .wav ? kAudioFileWAVEType : kAudioFileAIFFType
            asbd.mFormatID = kAudioFormatLinearPCM
            asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
                | (format == .aiff ? kAudioFormatFlagIsBigEndian : 0)
            asbd.mBitsPerChannel = bits
            asbd.mBytesPerFrame = bits / 8 * UInt32(channels)
            asbd.mBytesPerPacket = asbd.mBytesPerFrame
            asbd.mFramesPerPacket = 1
            bitrate = nil
        case .flac:
            fileType = kAudioFileFLACType
            asbd.mFormatID = kAudioFormatFLAC
            asbd.mFormatFlags = losslessFlag
            bitrate = nil
        case .m4a:
            fileType = kAudioFileM4AType
            asbd.mFormatID = useAAC ? kAudioFormatMPEG4AAC : kAudioFormatAppleLossless
            asbd.mFormatFlags = useAAC ? 0 : losslessFlag
            bitrate = useAAC ? options.bitrate * 1000 : nil
        case .opus:
            fileType = kAudioFileCAFType
            asbd.mFormatID = kAudioFormatOpus
            asbd.mFramesPerPacket = 960  // 20 ms, the usual Opus frame
            bitrate = options.bitrate * 1000
        default:
            throw ConversionError.unsupportedConversion(from: .audio, to: format)
        }

        if asbd.mFormatID != kAudioFormatLinearPCM {
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, nil, &size, &asbd), "prepare the \(format.displayName) encoder")
        }
        fileFormat = asbd
    }

    /// Decoded audio as the encoder wants it: interleaved 32-bit float at the target rate.
    var readerSettings: [String: Any] {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
        return [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
        ]
    }

    var clientFormat: AudioStreamBasicDescription {
        let bytes = UInt32(4 * channels)
        return AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytes, mFramesPerPacket: 1, mBytesPerFrame: bytes,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0
        )
    }

    func createFile(at url: URL) throws -> ExtAudioFileRef {
        var fileFormat = fileFormat
        var file: ExtAudioFileRef?
        let status = ExtAudioFileCreateWithURL(url as CFURL, fileType, &fileFormat, nil, AudioFileFlags.eraseFile.rawValue, &file)
        guard status == noErr, let file else { throw ConversionError.encoderUnavailable(format.displayName) }

        do {
            var client = clientFormat
            try check(ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                                              UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client), "set up the encoder")
            if let bitrate { try applyBitrate(bitrate, to: file) }
        } catch {
            ExtAudioFileDispose(file)
            throw error
        }
        return file
    }

    /// Picks the closest data rate the encoder supports at or below the request.
    private func applyBitrate(_ requested: Int, to file: ExtAudioFileRef) throws {
        var converter: AudioConverterRef?
        var size = UInt32(MemoryLayout<AudioConverterRef?>.size)
        try check(ExtAudioFileGetProperty(file, kExtAudioFileProperty_AudioConverter, &size, &converter), "set the bitrate")
        guard let converter else { return }

        var rate = UInt32(requested)
        var listSize: UInt32 = 0
        if AudioConverterGetPropertyInfo(converter, kAudioConverterApplicableEncodeBitRates, &listSize, nil) == noErr, listSize > 0 {
            var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(listSize) / MemoryLayout<AudioValueRange>.size)
            if AudioConverterGetProperty(converter, kAudioConverterApplicableEncodeBitRates, &listSize, &ranges) == noErr {
                let allowed = ranges.map { UInt32($0.mMaximum) }.sorted()
                rate = allowed.last(where: { $0 <= rate }) ?? allowed.first ?? rate
            }
        }
        try check(AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, UInt32(MemoryLayout<UInt32>.size), &rate), "set the bitrate")
        // Setting an empty converter config makes ExtAudioFile pick up the new bitrate.
        var config: UnsafeRawPointer? = nil
        try check(ExtAudioFileSetProperty(file, kExtAudioFileProperty_ConverterConfig, UInt32(MemoryLayout<UnsafeRawPointer?>.size), &config), "set the bitrate")
    }
}

func check(_ status: OSStatus, _ action: String) throws {
    guard status == noErr else {
        throw ConversionError.failed("Couldn’t \(action) (\(MediaProbe.fourCC(FourCharCode(bitPattern: status))), \(status)).")
    }
}
