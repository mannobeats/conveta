import ConvetaKit
import SwiftUI

/// The files to convert, one row each.
struct QueueList: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var queue = state.queue
        List(selection: $queue.selection) {
            ForEach(queue.jobs) { job in
                JobRow(job: job)
                    .tag(job.id)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: ConversionJob.ID.self) { ids in
            JobMenu(ids: ids.isEmpty ? queue.selection : ids)
        } primaryAction: { ids in
            queue.revealOutputs(of: ids)
        }
        .onDeleteCommand { queue.remove(queue.selection) }
        .onKeyPress(.escape) {
            guard !queue.selection.isEmpty else { return .ignored }
            queue.selection = []
            return .handled
        }
    }
}

/// The right-click menu for one or more rows.
private struct JobMenu: View {
    @Environment(AppState.self) private var state
    let ids: Set<ConversionJob.ID>

    var body: some View {
        let queue = state.queue
        let jobs = queue.jobs.filter { ids.contains($0.id) }
        Button("Convert") { queue.convert(jobs) }
            .disabled(!jobs.contains(where: \.state.isStartable) || queue.isRunning)
        if jobs.contains(where: \.state.isActive) {
            Button("Stop") { queue.cancel(ids) }
        }
        Divider()
        Button("Show Converted File in Finder") { queue.revealOutputs(of: ids) }
            .disabled(!jobs.contains { $0.output != nil })
        Button("Show Original in Finder") { queue.revealSources(of: ids) }
        Divider()
        Button("Remove from List", role: .destructive) { queue.remove(ids) }
    }
}

/// One file: thumbnail, name, what it is, and where its conversion stands.
struct JobRow: View {
    let job: ConversionJob
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(job: job)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(detailLine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            JobStatus(job: job, isHovered: isHovered)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .overlay(alignment: .bottom) {
            if job.state == .converting {
                ProgressBar(value: job.progress, tint: job.kind.map(Theme.color(for:)) ?? .accentColor)
                    .transition(.opacity)
            }
        }
        .animation(Theme.motion, value: job.state)
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        switch job.state {
        case .unsupported(let reason), .failed(let reason):
            return reason
        default:
            var parts: [String] = []
            if let info = job.info {
                parts.append(info.fileSize.fileSizeText)
                if !info.details.isEmpty { parts.append(info.details) }
            }
            return parts.isEmpty ? job.source.deletingLastPathComponent().path(percentEncoded: false) : parts.joined(separator: " · ")
        }
    }
}

private struct Thumbnail: View {
    let job: ConversionJob

    var body: some View {
        ZStack {
            // Audio thumbnails are only a generic icon; the coloured badge says more.
            if let image = job.thumbnail, job.kind != .audio {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Theme.rowThumbnail, height: Theme.rowThumbnail)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
                    .transition(.opacity)
            } else if let kind = job.kind {
                KindBadge(kind: kind)
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: job.state.isUnsupported ? "questionmark" : "doc")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: Theme.rowThumbnail, height: Theme.rowThumbnail)
            }
        }
        .animation(Theme.motion, value: job.thumbnail != nil)
        .accessibilityHidden(true)
    }
}

/// The right side of a row. Its width is fixed so names line up while states change.
private struct JobStatus: View {
    let job: ConversionJob
    let isHovered: Bool
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .frame(minWidth: 150, alignment: .trailing)
    }

    @ViewBuilder private var content: some View {
        switch job.state {
        case .probing:
            ProgressView().controlSize(.small)
        case .ready, .cancelled:
            if job.state == .cancelled {
                Text("Stopped").font(.caption).foregroundStyle(.secondary)
            }
            arrowChip
        case .queued:
            Text("Waiting").font(.caption).foregroundStyle(.secondary)
            arrowChip
        case .converting:
            Text(job.progress, format: .percent.precision(.fractionLength(0)))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: job.progress))
            Button("Stop", systemImage: "xmark.circle.fill") { state.queue.cancel([job.id]) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Stop converting this file")
        case .done:
            doneSummary
        case .failed:
            Button("Try Again", systemImage: "arrow.clockwise") { state.queue.convert([job]) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Try again")
                .disabled(state.queue.isRunning)
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("Failed")
        case .unsupported:
            Text("Can’t Convert").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var arrowChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            FormatChip(format: job.settings.format)
        }
    }

    @ViewBuilder private var doneSummary: some View {
        if isHovered, job.output != nil {
            Button("Show in Finder", systemImage: "magnifyingglass") { state.queue.revealOutputs(of: [job.id]) }
                .buttonStyle(.borderless)
                .font(.caption)
                .transition(.opacity)
        } else if let size = job.outputSize {
            VStack(alignment: .trailing, spacing: 1) {
                Text(size.fileSizeText).font(.callout.monospacedDigit())
                if let change = job.sizeChange, abs(change) >= 0.01 {
                    Text(change, format: .percent.precision(.fractionLength(0)).sign(strategy: .always()))
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(change < 0 ? .green : .secondary)
                }
            }
        }
        Image(systemName: "checkmark.circle.fill")
            .font(.title3)
            .foregroundStyle(.green)
            .symbolEffect(.bounce, value: job.state == .done)
            .accessibilityLabel("Converted")
    }
}

/// A two-point bar along the bottom of a converting row.
struct ProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(tint.gradient)
                .frame(width: max(4, proxy.size.width * value))
                .animation(.linear(duration: 0.2), value: value)
        }
        .frame(height: 2)
        .padding(.horizontal, 4)
        .accessibilityLabel("Progress")
        .accessibilityValue(Text(value, format: .percent))
    }
}
