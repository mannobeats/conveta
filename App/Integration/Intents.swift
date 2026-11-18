import AppIntents
import ConvetaKit
import Foundation

/// The formats as Shortcuts shows them. App Intents needs these as literals in the app target,
/// so they mirror ``OutputFormat`` case for case (checked by the self-test).
enum IntentFormat: String, AppEnum {
    case mp4, mov, m4v, gif, m4a, wav, aiff, flac, opus, jpeg, png, heic, avif, tiff, bmp, pdf

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Format"

    static let caseDisplayRepresentations: [IntentFormat: DisplayRepresentation] = [
        .mp4: DisplayRepresentation(title: "MP4", subtitle: "Video that plays everywhere"),
        .mov: DisplayRepresentation(title: "MOV", subtitle: "Video for Apple and editing apps"),
        .m4v: DisplayRepresentation(title: "M4V", subtitle: "Video for Apple TV"),
        .gif: DisplayRepresentation(title: "GIF", subtitle: "Short looping animation"),
        .m4a: DisplayRepresentation(title: "M4A", subtitle: "Small audio, great quality"),
        .wav: DisplayRepresentation(title: "WAV", subtitle: "Uncompressed audio"),
        .aiff: DisplayRepresentation(title: "AIFF", subtitle: "Uncompressed audio, Apple"),
        .flac: DisplayRepresentation(title: "FLAC", subtitle: "Lossless audio"),
        .opus: DisplayRepresentation(title: "Opus", subtitle: "Smallest audio"),
        .jpeg: DisplayRepresentation(title: "JPEG", subtitle: "Photos, universal"),
        .png: DisplayRepresentation(title: "PNG", subtitle: "Lossless image with transparency"),
        .heic: DisplayRepresentation(title: "HEIC", subtitle: "Half the size of JPEG"),
        .avif: DisplayRepresentation(title: "AVIF", subtitle: "Smallest image for the web"),
        .tiff: DisplayRepresentation(title: "TIFF", subtitle: "Lossless image for print"),
        .bmp: DisplayRepresentation(title: "BMP", subtitle: "Uncompressed bitmap"),
        .pdf: DisplayRepresentation(title: "PDF", subtitle: "Document"),
    ]

    var outputFormat: OutputFormat? { OutputFormat(rawValue: rawValue) }
}

/// "Convert Files" in Shortcuts. A shortcut built on it can be added to Finder as a Quick Action.
struct ConvertFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Convert Files"
    static let description = IntentDescription("Converts videos, audio, images and PDFs with Conveta, saving each beside the original.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Files", supportedContentTypes: [.movie, .audio, .image, .pdf])
    var files: [IntentFile]

    @Parameter(title: "Format")
    var format: IntentFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$files) to \(\.$format)")
    }

    func perform() async throws -> some IntentResult {
        let urls = files.compactMap(\.fileURL)
        guard !urls.isEmpty else { throw $files.needsValueError("Which files should Conveta convert?") }
        await AppState.shared.open(urls, format: format.outputFormat, start: true)
        return .result()
    }
}

/// "Open Conveta" with files, without starting a conversion.
struct AddFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Files to Conveta"
    static let description = IntentDescription("Adds files to Conveta's list so you can choose formats before converting.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Files", supportedContentTypes: [.movie, .audio, .image, .pdf])
    var files: [IntentFile]

    func perform() async throws -> some IntentResult {
        await AppState.shared.open(files.compactMap(\.fileURL))
        return .result()
    }
}
