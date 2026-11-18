import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// What Conveta knows about a source file before converting it.
public struct MediaInfo: Sendable, Hashable {
    public var kind: MediaKind
    public var contentType: UTType
    public var fileSize: Int64
    public var duration: Double?
    public var pixelSize: CGSize?
    public var frameRate: Double?
    public var codec: String?
    public var sampleRate: Double?
    public var channels: Int?
    public var hasAudio = false
    public var frameCount = 1
    public var pageCount: Int?

    /// A compact line such as "1920×1080 · 0:42 · H.264".
    public var details: String {
        var parts: [String] = []
        if let pixelSize { parts.append("\(Int(pixelSize.width))×\(Int(pixelSize.height))") }
        if let duration, duration > 0 { parts.append(Self.formatDuration(duration)) }
        if let codec { parts.append(codec) }
        if kind == .audio, let sampleRate { parts.append(String(format: "%g kHz", sampleRate / 1000)) }
        if let pageCount { parts.append(pageCount == 1 ? "1 page" : "\(pageCount) pages") }
        if kind == .image, frameCount > 1 { parts.append("\(frameCount) frames") }
        return parts.joined(separator: " · ")
    }

    public static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

public enum ProbeError: LocalizedError, Equatable {
    case unsupportedType(String)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedType(let ext): "Conveta can’t convert .\(ext) files yet."
        case .unreadable(let name): "“\(name)” couldn’t be read. It may be damaged or protected."
        }
    }
}

/// Reads a file's kind and properties without decoding it.
public enum MediaProbe {
    public static func probe(_ url: URL) async throws -> MediaInfo {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        let size = Int64(values?.fileSize ?? 0)
        guard let kind = MediaKind(contentType: type) else {
            throw ProbeError.unsupportedType(url.pathExtension.lowercased())
        }
        switch kind {
        case .image: return try probeImage(url, type: type, size: size)
        case .document: return try probeDocument(url, type: type, size: size)
        case .video, .audio: return try await probeAudiovisual(url, type: type, size: size)
        }
    }

    private static func probeImage(_ url: URL, type: UTType, size: Int64) throws -> MediaInfo {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw ProbeError.unreadable(url.lastPathComponent) }
        var width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        var height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        if let orientation = props[kCGImagePropertyOrientation] as? Int, orientation >= 5 { swap(&width, &height) }
        var info = MediaInfo(kind: .image, contentType: type, fileSize: size)
        info.pixelSize = CGSize(width: width, height: height)
        info.frameCount = CGImageSourceGetCount(source)
        info.codec = type.preferredFilenameExtension?.uppercased()
        return info
    }

    private static func probeDocument(_ url: URL, type: UTType, size: Int64) throws -> MediaInfo {
        guard let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0 else {
            throw ProbeError.unreadable(url.lastPathComponent)
        }
        var info = MediaInfo(kind: .document, contentType: type, fileSize: size)
        info.pageCount = document.numberOfPages
        return info
    }

    private static func probeAudiovisual(_ url: URL, type: UTType, size: Int64) async throws -> MediaInfo {
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isReadable)) == true else {
            if !AVURLAsset.audiovisualTypes().contains(AVFileType(type.identifier)) {
                throw ProbeError.unsupportedType(url.pathExtension.lowercased())
            }
            throw ProbeError.unreadable(url.lastPathComponent)
        }
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !videoTracks.isEmpty || !audioTracks.isEmpty else {
            throw ProbeError.unreadable(url.lastPathComponent)
        }

        var info = MediaInfo(kind: videoTracks.isEmpty ? .audio : .video, contentType: type, fileSize: size)
        info.duration = duration.isFinite ? duration : nil
        info.hasAudio = !audioTracks.isEmpty

        if let track = videoTracks.first {
            let (natural, transform, fps, formats) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)
            let shown = natural.applying(transform)
            info.pixelSize = CGSize(width: abs(shown.width).rounded(), height: abs(shown.height).rounded())
            info.frameRate = Double(fps)
            info.codec = formats.first.map { codecName(CMFormatDescriptionGetMediaSubType($0)) }
        } else if let track = audioTracks.first {
            let formats = try await track.load(.formatDescriptions)
            if let format = formats.first {
                info.codec = codecName(CMFormatDescriptionGetMediaSubType(format))
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                    info.sampleRate = asbd.mSampleRate
                    info.channels = Int(asbd.mChannelsPerFrame)
                }
            }
        }
        return info
    }

    /// A friendly name for a codec four-character code.
    static func codecName(_ code: FourCharCode) -> String {
        switch code {
        case kCMVideoCodecType_H264: "H.264"
        case kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha: "HEVC"
        case kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes422HQ,
             kCMVideoCodecType_AppleProRes422LT, kCMVideoCodecType_AppleProRes422Proxy: "ProRes 422"
        case kCMVideoCodecType_AppleProRes4444, kCMVideoCodecType_AppleProRes4444XQ: "ProRes 4444"
        case kCMVideoCodecType_MPEG4Video: "MPEG-4"
        case kCMVideoCodecType_MPEG2Video: "MPEG-2"
        case kCMVideoCodecType_AV1: "AV1"
        case kCMVideoCodecType_VP9: "VP9"
        case kCMVideoCodecType_JPEG: "Motion JPEG"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2: "AAC"
        case kAudioFormatMPEGLayer3: "MP3"
        case kAudioFormatAppleLossless: "Apple Lossless"
        case kAudioFormatFLAC: "FLAC"
        case kAudioFormatOpus: "Opus"
        case kAudioFormatLinearPCM: "PCM"
        case kAudioFormatAC3: "AC-3"
        case kAudioFormatEnhancedAC3: "E-AC-3"
        default: fourCC(code)
        }
    }

    static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }
}
