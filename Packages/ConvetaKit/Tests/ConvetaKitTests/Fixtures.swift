import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ConvetaKit

/// Builds real media files for tests, so no binary fixtures live in the repo.
/// Everything is written under a fresh temporary folder per test.
struct Fixtures {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ConvetaTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: folder) }

    func url(_ name: String) -> URL { folder.appending(path: name) }

    // MARK: Images

    /// A gradient image; with `alpha`, its left half is transparent.
    static func makeImage(width: Int, height: Int, alpha: Bool = false) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in stride(from: 0, to: width, by: 4) {
            context.setFillColor(red: CGFloat(x) / CGFloat(width), green: 0.4, blue: 1 - CGFloat(x) / CGFloat(width), alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 4, height: height))
        }
        if alpha { context.clear(CGRect(x: 0, y: 0, width: width / 2, height: height)) }
        return context.makeImage()!
    }

    func writeImage(_ name: String, type: UTType, width: Int = 300, height: Int = 200, alpha: Bool = false,
                    properties: [CFString: Any] = [:]) throws -> URL {
        let url = url(name)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, Self.makeImage(width: width, height: height, alpha: alpha), properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.write(name) }
        return url
    }

    func writeAnimatedGIF(_ name: String, frames: Int) throws -> URL {
        let url = url(name)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil)!
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<frames {
            CGImageDestinationAddImage(destination, Self.makeImage(width: 120 + index * 2, height: 80),
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.write(name) }
        return url
    }

    /// A PDF whose second page is landscape and whose third is stored rotated by 90°.
    func writePDF(_ name: String, pages: Int) throws -> URL {
        let url = url(name)
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        for page in 0..<pages {
            var pageBox = page == 1 ? CGRect(x: 0, y: 0, width: 792, height: 612) : box
            let info: [CFString: Any] = [kCGPDFContextMediaBox: Data(bytes: &pageBox, count: MemoryLayout<CGRect>.size)]
            context.beginPDFPage(info as CFDictionary)
            context.setFillColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1)
            context.fill(CGRect(x: 72, y: 72, width: 200, height: 100))
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    // MARK: Audio and video

    /// A stereo sine tone as 16-bit WAV.
    func writeTone(_ name: String, seconds: Double = 1.5, sampleRate: Double = 44_100, channels: AVAudioChannelCount = 2) throws -> URL {
        let url = url(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 16,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            let samples = buffer.floatChannelData![channel]
            for i in 0..<Int(frames) { samples[i] = 0.4 * sin(2 * .pi * 440 * Float(i) / Float(sampleRate)) }
        }
        try file.write(from: buffer)
        return url
    }

    /// An H.264 movie with moving colour bars, optionally with a sound track and a 90° rotation.
    func writeMovie(_ name: String, width: Int = 640, height: Int = 360, seconds: Double = 1.5, fps: Int32 = 30,
                    withAudio: Bool = true, rotated: Bool = false) async throws -> URL {
        let silent = url("video-only-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: silent, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        if rotated { input.transform = CGAffineTransform(rotationAngle: .pi / 2) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let frameCount = Int(seconds * Double(fps))
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            Self.paint(buffer!, frame: frame)
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? FixtureError.write(name) }

        let output = url(name)
        guard withAudio else {
            try FileManager.default.moveItem(at: silent, to: output)
            return output
        }
        let tone = try writeTone("tone-\(UUID().uuidString).wav", seconds: seconds)
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: silent), audioAsset = AVURLAsset(url: tone)
        let videoTrack = try await videoAsset.loadTracks(withMediaType: .video)[0]
        let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio)[0]
        let range = CMTimeRange(start: .zero, duration: try await videoAsset.load(.duration))
        let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try compositionVideo.insertTimeRange(range, of: videoTrack, at: .zero)
        compositionVideo.preferredTransform = try await videoTrack.load(.preferredTransform)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            .insertTimeRange(range, of: audioTrack, at: .zero)
        let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
        try await export.export(to: output, as: .mov)
        return output
    }

    private static func paint(_ buffer: CVPixelBuffer, frame: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = base + y * row + x * 4
                pixel[0] = UInt8((x + frame * 4) % 256)
                pixel[1] = UInt8(y % 256)
                pixel[2] = UInt8((frame * 8) % 256)
                pixel[3] = 255
            }
        }
    }
}

enum FixtureError: Error { case write(String) }

/// Reads back what a conversion produced.
enum Inspect {
    static func imageSize(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }

    static func imageType(_ url: URL) -> String? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceGetType($0) as String? }
    }

    static func frameCount(_ url: URL) -> Int {
        CGImageSourceCreateWithURL(url as CFURL, nil).map(CGImageSourceGetCount) ?? 0
    }

    static func properties(_ url: URL) -> [CFString: Any] {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
    }

    static func codec(_ url: URL, _ type: AVMediaType) async throws -> FourCharCode? {
        let track = try await AVURLAsset(url: url).loadTracks(withMediaType: type).first
        return try await track?.load(.formatDescriptions).first.map(CMFormatDescriptionGetMediaSubType)
    }

    /// Copied out by value: the pointer AVAudioFormat hands out dies with the file object.
    static func audioFormat(_ url: URL) throws -> AudioStreamBasicDescription {
        let file = try AVAudioFile(forReading: url)
        return file.fileFormat.streamDescription.pointee
    }
}
