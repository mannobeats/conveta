import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Still and animated images through ImageIO: any format the Mac reads (RAW, WebP, HEIC, PSD...)
/// to JPEG, PNG, HEIC, AVIF, TIFF, GIF, BMP or a one-page PDF.
struct ImageConverter: Converter {
    func convert(_ request: ConversionRequest, progress: @escaping ProgressHandler) async throws -> ConversionOutput {
        let options = request.settings.image
        guard let source = CGImageSourceCreateWithURL(request.source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0
        else { throw ConversionError.unreadable }

        let format = request.settings.format
        if format == .pdf {
            let image = try Self.decode(source, index: 0, maxDimension: options.maxDimension)
            try PDFWriter.writeImage(image, to: request.destination)
            progress(1)
            return .file
        }

        // Animated GIFs stay animated when the output is GIF; every other format takes the first frame.
        let frameCount = format == .gif ? CGImageSourceGetCount(source) : 1
        guard let destination = CGImageDestinationCreateWithURL(
            request.destination as CFURL, format.contentType.identifier as CFString, frameCount, nil
        ) else { throw ConversionError.encoderUnavailable(format.displayName) }

        if format == .gif, frameCount > 1 {
            let loop = (CGImageSourceCopyProperties(source, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let loopCount = loop?[kCGImagePropertyGIFLoopCount] as? Int ?? 0
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopCount]] as CFDictionary)
        }

        for index in 0..<frameCount {
            try Task.checkCancellation()
            var image = try Self.decode(source, index: index, maxDimension: options.maxDimension)
            if !format.supportsTransparency, image.hasAlpha {
                image = try Self.flatten(image)
            }
            let properties = Self.frameProperties(source: source, index: index, format: format, options: options)
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            progress(Double(index + 1) / Double(frameCount + 1))
        }
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.failed("The \(format.displayName) file couldn’t be written.")
        }
        progress(1)
        return .file
    }

    /// Decodes one frame upright (EXIF orientation applied), shrunk to `maxDimension` if given.
    static func decode(_ source: CGImageSource, index: Int, maxDimension: Int?) throws -> CGImage {
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longest = max(width, height)
        let target = min(maxDimension ?? longest, longest)
        guard target > 0 else { throw ConversionError.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            throw ConversionError.unreadable
        }
        return image
    }

    /// Draws an image with transparency onto white, for formats without an alpha channel.
    static func flatten(_ image: CGImage) throws -> CGImage {
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw ConversionError.failed("Not enough memory to convert this image.") }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        guard let flat = context.makeImage() else { throw ConversionError.failed("Not enough memory to convert this image.") }
        return flat
    }

    /// Metadata to write with a frame: the original's (unless stripped), upright, plus encoder settings.
    static func frameProperties(source: CGImageSource, index: Int, format: OutputFormat, options: ImageOptions) -> [CFString: Any] {
        var properties: [CFString: Any] = [:]
        if !options.stripMetadata, let original = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
                        kCGImagePropertyTIFFDictionary, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
                if let value = original[key] { properties[key] = value }
            }
            // The pixels are already upright, so the stored orientation must say so.
            if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                properties[kCGImagePropertyTIFFDictionary] = tiff
            }
        }
        properties[kCGImagePropertyOrientation] = 1
        if format == .gif,
           let gif = (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any],
           let delay = gif[kCGImagePropertyGIFUnclampedDelayTime] ?? gif[kCGImagePropertyGIFDelayTime] {
            properties[kCGImagePropertyGIFDictionary] = [kCGImagePropertyGIFDelayTime: delay]
        }
        if format.isLossy, format != .gif {
            properties[kCGImageDestinationLossyCompressionQuality] = options.quality.imageCompression
        }
        return properties
    }
}

extension CGImage {
    var hasAlpha: Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }
}

/// Writes images as PDF pages, one page per image, sized at 72 points per pixel.
enum PDFWriter {
    static func writeImage(_ image: CGImage, to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw ConversionError.failed("The PDF couldn’t be created.")
        }
        context.beginPDFPage(nil)
        context.draw(image, in: box)
        context.endPDFPage()
        context.closePDF()
    }
}
