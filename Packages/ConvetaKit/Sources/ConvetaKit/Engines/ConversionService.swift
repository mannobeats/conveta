import Foundation

/// The one entry point the app uses: picks the right converter, writes into a hidden working
/// folder next to the final location, and moves the result into place only when it is complete.
/// A failed or cancelled job never leaves a half-written file behind, and nothing is overwritten.
public struct ConversionService: Sendable {
    public init() {}

    /// Converts `source` into `directory`, returning the URL of the file or folder written.
    public func convert(
        _ source: URL,
        info: MediaInfo,
        settings: ConversionSettings,
        into directory: URL,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> URL {
        let converter = try Self.converter(for: info.kind, format: settings.format)
        // Each job works in its own hidden folder beside the destination: same volume, so the final
        // move is instant, and any helper files an encoder makes are removed with the folder.
        let workspace = directory.appending(path: ".conveta-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        } catch {
            throw ConversionError.noWriteAccess(directory)
        }
        defer { try? FileManager.default.removeItem(at: workspace) }

        let working = workspace.appending(path: "output.\(settings.format.fileExtension)")
        let request = ConversionRequest(source: source, destination: working, settings: settings, info: info)
        let output = try await converter.convert(request, progress: progress)
        try Task.checkCancellation()

        let baseName = source.deletingPathExtension().lastPathComponent
        let isFolder = if case .folder = output { true } else { false }
        return try OutputNaming.moveIntoPlace(working, in: directory, baseName: baseName,
                                              pathExtension: isFolder ? nil : settings.format.fileExtension)
    }

    /// Whether a file of `kind` can become `format`.
    public static func canConvert(_ kind: MediaKind, to format: OutputFormat) -> Bool {
        kind.outputFormats.contains(format)
    }

    static func converter(for kind: MediaKind, format: OutputFormat) throws -> any Converter {
        guard canConvert(kind, to: format) else { throw ConversionError.unsupportedConversion(from: kind, to: format) }
        switch (kind, format.kind) {
        case (.document, _): return PDFPageConverter()
        case (.image, _): return ImageConverter()
        case (.video, .video): return VideoConverter()
        case (.video, .image): return AnimatedGIFConverter()
        case (.video, .audio), (.audio, .audio): return AudioConverter()
        default: throw ConversionError.unsupportedConversion(from: kind, to: format)
        }
    }
}

/// Output names: "Clip.mov" becomes "Clip.mp4", or "Clip 2.mp4" when that exists.
public enum OutputNaming {
    public static func candidate(in directory: URL, baseName: String, pathExtension: String?, attempt: Int) -> URL {
        let name = attempt <= 1 ? baseName : "\(baseName) \(attempt)"
        let url = directory.appending(path: name, directoryHint: pathExtension == nil ? .isDirectory : .notDirectory)
        return pathExtension.map { url.appendingPathExtension($0) } ?? url
    }

    /// Renames `item` to the first free name. Safe against another job taking a name at the same moment,
    /// because `moveItem` refuses to replace an existing file and the next name is tried.
    static func moveIntoPlace(_ item: URL, in directory: URL, baseName: String, pathExtension: String?) throws -> URL {
        let manager = FileManager.default
        for attempt in 1...10_000 {
            let target = candidate(in: directory, baseName: baseName, pathExtension: pathExtension, attempt: attempt)
            if manager.fileExists(atPath: target.path) { continue }
            do {
                try manager.moveItem(at: item, to: target)
                return target
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        try? manager.removeItem(at: item)
        throw ConversionError.failed("There’s no free name for “\(baseName)” in this folder.")
    }
}
