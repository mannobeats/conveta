import AppIntents
import ConvetaKit
import Foundation

/// The formats as Shortcuts shows them. App Intents needs these as literals in the app target,
/// so they mirror ``OutputFormat`` case for case (checked by the self-test).
enum IntentFormat: String, AppEnum {
    case mp4, mov, m4v, mkv, webm, avi, gif, mp3, m4a, aac, wav, aiff, flac, ogg, opus, wma
    case jpeg, png, heic, avif, webp, tiff, bmp, pdf

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Format"

    static let caseDisplayRepresentations: [IntentFormat: DisplayRepresentation] = [
        .mp4: DisplayRepresentation(title: "MP4", subtitle: "Video that plays everywhere"),
        .mov: DisplayRepresentation(title: "MOV", subtitle: "Video for Apple and editing apps"),
        .m4v: DisplayRepresentation(title: "M4V", subtitle: "Video for Apple TV"),
        .mkv: DisplayRepresentation(title: "MKV", subtitle: "Flexible video, keeps every track"),
        .webm: DisplayRepresentation(title: "WebM", subtitle: "Open video for the web"),
        .avi: DisplayRepresentation(title: "AVI", subtitle: "Video for older players"),
        .gif: DisplayRepresentation(title: "GIF", subtitle: "Short looping animation"),
        .mp3: DisplayRepresentation(title: "MP3", subtitle: "Audio that plays on everything"),
        .aac: DisplayRepresentation(title: "AAC", subtitle: "Raw AAC audio"),
        .ogg: DisplayRepresentation(title: "Ogg", subtitle: "Open Vorbis audio"),
        .wma: DisplayRepresentation(title: "WMA", subtitle: "Windows Media audio"),
        .webp: DisplayRepresentation(title: "WebP", subtitle: "Small images for the web"),
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

/// "Download Video" in Shortcuts: a link from YouTube, Instagram, TikTok and more, saved as any format.
struct DownloadVideoIntent: AppIntent {
    static let title: LocalizedStringResource = "Download Video"
    static let description = IntentDescription("Downloads a video from YouTube, Instagram, TikTok and other sites, and saves it in the format you choose.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Link")
    var link: URL

    @Parameter(title: "Format", default: .mp4)
    var format: IntentFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Download \(\.$link) as \(\.$format)")
    }

    func perform() async throws -> some IntentResult {
        guard LinkDetector.isWebLink(link) else { throw $link.needsValueError("Which web link should Conveta download?") }
        await AppState.shared.queue.addLinks([link], format: format.outputFormat, start: true)
        return .result()
    }
}
