import CoreGraphics
import Foundation
import ImageIO

/// Renders PDF pages to images. One page becomes one file; several pages become a folder
/// of files named "1.png", "2.png", ... (zero-padded so Finder sorts them).
struct PDFPageConverter: Converter {
    func convert(_ request: ConversionRequest, progress: @escaping ProgressHandler) async throws -> ConversionOutput {
        guard let document = CGPDFDocument(request.source as CFURL), document.numberOfPages > 0 else {
            throw ConversionError.unreadable
        }
        let format = request.settings.format
        let pageCount = document.numberOfPages
        let scale = CGFloat(request.settings.document.dotsPerInch) / 72

        if pageCount == 1 {
            try render(document.page(at: 1)!, scale: scale, format: format, quality: request.settings.image.quality, to: request.destination)
            progress(1)
            return .file
        }

        let folder = request.destination
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let digits = String(pageCount).count
        for number in 1...pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: number) else { continue }
            let name = String(repeating: "0", count: digits - String(number).count) + String(number)
            let url = folder.appending(path: name).appendingPathExtension(format.fileExtension)
            try render(page, scale: scale, format: format, quality: request.settings.image.quality, to: url)
            progress(Double(number) / Double(pageCount))
        }
        return .folder(count: pageCount)
    }

    private func render(_ page: CGPDFPage, scale: CGFloat, format: OutputFormat, quality: Quality, to url: URL) throws {
        let box = page.getBoxRect(.cropBox)
        let rotated = page.rotationAngle % 180 != 0
        let pageSize = rotated ? CGSize(width: box.height, height: box.width) : box.size
        let width = max(1, Int((pageSize.width * scale).rounded()))
        let height = max(1, Int((pageSize.height * scale).rounded()))
        guard width * height <= 30_000 * 30_000 / 4,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ConversionError.failed("This page is too large to render at this resolution.") }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        // Rotate around the page so the rendered image is upright, then move the crop box to the origin.
        context.translateBy(x: pageSize.width / 2, y: pageSize.height / 2)
        context.rotate(by: -CGFloat(page.rotationAngle) * .pi / 180)
        context.translateBy(x: -box.width / 2 - box.minX, y: -box.height / 2 - box.minY)
        context.drawPDFPage(page)

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, format.contentType.identifier as CFString, 1, nil)
        else { throw ConversionError.encoderUnavailable(format.displayName) }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: Double(scale * 72),
            kCGImagePropertyDPIHeight: Double(scale * 72),
        ]
        if format.isLossy { properties[kCGImageDestinationLossyCompressionQuality] = quality.imageCompression }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.failed("The \(format.displayName) file couldn’t be written.")
        }
    }
}
