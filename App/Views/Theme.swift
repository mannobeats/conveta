import ConvetaKit
import SwiftUI

/// Conveta's small set of visual decisions. Chrome stays native; content gets one idea:
/// each kind of media has its own colour, used for its icon, its format chip and its progress.
enum Theme {
    static let rowThumbnail: CGFloat = 40
    static let cornerRadius: CGFloat = 8
    static let chipRadius: CGFloat = 6

    static func color(for kind: MediaKind) -> Color {
        switch kind {
        case .video: .blue
        case .audio: Color(red: 1.0, green: 0.36, blue: 0.32)    // coral
        case .image: .teal
        case .document: Color(red: 1.0, green: 0.66, blue: 0.0)  // amber
        }
    }

    static func gradient(for kind: MediaKind) -> LinearGradient {
        let base = color(for: kind)
        return LinearGradient(colors: [base.mix(with: .white, by: 0.15), base.mix(with: .black, by: 0.1)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The motion every state change uses: quick and calm, nothing bouncy.
    static let motion = Animation.smooth(duration: 0.25)
}

/// A compact label with the media kind's colour, for formats such as "MP4".
struct FormatChip: View {
    let format: OutputFormat
    var prominent = false

    var body: some View {
        Text(format.displayName)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.color(for: format.kind)))
            .background(
                RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(Theme.gradient(for: format.kind)) : AnyShapeStyle(Theme.color(for: format.kind).opacity(0.14)))
            )
            .accessibilityLabel("Converts to \(format.displayName)")
    }
}

extension Int64 {
    var fileSizeText: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
