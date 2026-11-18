import ConvetaKit
import SwiftUI

/// Conversion settings for the selected files, or for every waiting file when nothing is selected.
/// Changes apply at once and become the starting point for the next file of the same kind.
struct InspectorView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let targets = state.queue.editingTargets
        if !targets.isEmpty {
            SettingsForm(targets: targets)
        } else {
            ContentUnavailableView {
                Label("No Files to Set Up", systemImage: "slider.horizontal.3")
            } description: {
                Text(state.queue.jobs.isEmpty
                     ? "Add files, then choose what to convert them to."
                     : "Converted files can’t be changed. Select a file that’s waiting, or add more.")
            }
        }
    }
}

/// One section per kind of file being edited. Files of different kinds rarely share a format,
/// so each kind gets its own choice.
private struct SettingsForm: View {
    let targets: [ConversionJob]

    private var kinds: [MediaKind] {
        let present = Set(targets.compactMap(\.kind))
        return MediaKind.allCases.filter(present.contains)
    }

    var body: some View {
        Form {
            Section {
            } header: {
                InspectorHeader(targets: targets, kinds: kinds)
            }
            ForEach(kinds) { kind in
                let members = targets.filter { $0.kind == kind }
                KindSettings(kind: kind, count: members.count, showsKindTitle: kinds.count > 1,
                             current: members[0].settings)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

/// The format choice and options for the files of one kind.
private struct KindSettings: View {
    @Environment(AppState.self) private var state
    let kind: MediaKind
    let count: Int
    let showsKindTitle: Bool
    let current: ConversionSettings

    var body: some View {
        let format = current.format
        Section {
            FormatGrid(formats: kind.outputFormats, selected: format) { choice in
                withAnimation(Theme.motion) { update { $0.format = choice } }
            }
        } header: {
            if showsKindTitle {
                Label {
                    Text(title)
                } icon: {
                    KindBadge(kind: kind, size: 16)
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .textCase(nil)
            } else {
                Text("Convert To")
            }
        } footer: {
            Text(format.summary).foregroundStyle(.secondary)
        }

        switch (kind, format.kind) {
        case (_, .video):
            VideoSection(current: current, update: update)
        case (_, .audio):
            AudioSection(current: current, update: update)
        case (.video, _):
            AnimationSection(current: current, update: update)
        case (.document, _):
            PageSection(current: current, update: update, showsQuality: true)
        default:
            ImageSection(current: current, update: update)
        }
    }

    private var title: String {
        switch kind {
        case .video: count == 1 ? "1 Video" : "\(count) Videos"
        case .audio: count == 1 ? "1 Audio File" : "\(count) Audio Files"
        case .image: count == 1 ? "1 Image" : "\(count) Images"
        case .document: count == 1 ? "1 PDF" : "\(count) PDFs"
        }
    }

    private func update(_ change: (inout ConversionSettings) -> Void) {
        state.queue.updateSettings(kind: kind, change)
    }
}

private struct InspectorHeader: View {
    let targets: [ConversionJob]
    let kinds: [MediaKind]
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: -8) {
                ForEach(kinds) { KindBadge(kind: $0, size: 26) }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(state.queue.selection.isEmpty ? "All Waiting Files" : "\(targets.count == 1 ? targets[0].name : "\(targets.count) Files")")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(breakdown)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.bottom, 4)
    }

    private var breakdown: String {
        kinds.map { kind in
            let count = targets.filter { $0.kind == kind }.count
            let noun = switch kind {
            case .video: count == 1 ? "video" : "videos"
            case .audio: count == 1 ? "audio file" : "audio files"
            case .image: count == 1 ? "image" : "images"
            case .document: count == 1 ? "PDF" : "PDFs"
            }
            return "\(count) \(noun)"
        }
        .formatted(.list(type: .and))
    }
}

/// Output formats as tiles, grouped by what they produce.
struct FormatGrid: View {
    let formats: [OutputFormat]
    let selected: OutputFormat
    let choose: (OutputFormat) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        let groups = MediaKind.allCases.compactMap { kind -> (MediaKind, [OutputFormat])? in
            let members = formats.filter { $0.kind == kind }
            return members.isEmpty ? nil : (kind, members)
        }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups, id: \.0) { kind, members in
                VStack(alignment: .leading, spacing: 5) {
                    if groups.count > 1 {
                        Text(kind == .image && members == [.gif] ? "Animation" : kind.displayName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(members) { format in
                            FormatTile(format: format, isSelected: format == selected) { choose(format) }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct FormatTile: View {
    let format: OutputFormat
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(format.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 30)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(Theme.gradient(for: format.kind))
                                         : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.1 : 0.06)))
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(format.displayName): \(format.summary)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
