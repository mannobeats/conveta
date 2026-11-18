import AVFoundation
import ConvetaKit
import SwiftUI

/// Trim for one video or song: a filmstrip (or a plain bar for audio) with two handles.
struct TrimSection: View {
    let job: ConversionJob
    let duration: Double
    let update: SettingsUpdate

    @State private var frames: [NSImage] = []
    @State private var start = 0.0
    @State private var end = 1.0

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                TrimBar(frames: frames, isVideo: job.kind == .video, start: $start, end: $end) { commit() }
                    .frame(height: 44)
                    .padding(.horizontal, 6)  // room for the handles, which sit half outside the strip
                HStack {
                    Text(time(start * duration)).monospacedDigit()
                    Spacer()
                    Text("\(time((end - start) * duration)) long").foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Text(time(end * duration)).monospacedDigit()
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        } header: {
            HStack {
                Text("Trim")
                Spacer()
                if job.settings.trim != nil {
                    Button("Reset") {
                        start = 0; end = 1
                        commit()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        } footer: {
            Text("Drag the handles to keep only part of the \(job.kind == .video ? "video" : "recording").")
                .foregroundStyle(.secondary)
        }
        .task(id: job.id) {
            start = (job.settings.trim?.start ?? 0) / duration
            end = (job.settings.trim?.end ?? duration) / duration
            if job.kind == .video { frames = await Self.filmstrip(job.source, count: 8) }
        }
    }

    private func commit() {
        let range = TrimRange(start: start * duration, end: end * duration).meaningful(for: duration)
        update { $0.trim = range }
    }

    private func time(_ seconds: Double) -> String {
        let tenths = Int((seconds * 10).rounded()) % 10
        return MediaInfo.formatDuration(seconds.rounded(.down)) + ".\(tenths)"
    }

    static func filmstrip(_ url: URL, count: Int) async -> [NSImage] {
        let asset = AVURLAsset(url: url)
        guard let seconds = try? await asset.load(.duration).seconds, seconds > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 120)
        let times = (0..<count).map { CMTime(seconds: seconds * (Double($0) + 0.5) / Double(count), preferredTimescale: 600) }
        var images: [NSImage] = []
        for await result in generator.images(for: times) {
            if let image = try? result.image { images.append(NSImage(cgImage: image, size: .zero)) }
        }
        return images
    }
}

/// The strip with a highlighted kept range and two draggable handles.
private struct TrimBar: View {
    let frames: [NSImage]
    let isVideo: Bool
    @Binding var start: Double
    @Binding var end: Double
    let onCommit: () -> Void

    private let minimum = 0.02

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                strip
                    .frame(width: width)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                // Dim what will be cut.
                Rectangle().fill(.black.opacity(0.55)).frame(width: start * width)
                Rectangle().fill(.black.opacity(0.55)).frame(width: (1 - end) * width).offset(x: end * width)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.yellow, lineWidth: 3)
                    .frame(width: max(8, (end - start) * width))
                    .offset(x: start * width)
                    .allowsHitTesting(false)
                handle.offset(x: start * width - 5)
                    .gesture(drag(width) { start = min(max(0, $0), end - minimum) })
                handle.offset(x: end * width - 5)
                    .gesture(drag(width) { end = max(min(1, $0), start + minimum) })
            }
            .coordinateSpace(.named("trim"))
        }
        .accessibilityElement()
        .accessibilityLabel("Trim")
        .accessibilityValue("From \(Int(start * 100)) to \(Int(end * 100)) percent")
    }

    @ViewBuilder private var strip: some View {
        if isVideo, !frames.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                    Image(nsImage: frame).resizable().aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                }
            }
        } else {
            LinearGradient(colors: [Theme.color(for: isVideo ? .video : .audio).opacity(0.5), Theme.color(for: isVideo ? .video : .audio).opacity(0.25)],
                           startPoint: .leading, endPoint: .trailing)
        }
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.yellow)
            .frame(width: 10)
            .overlay(Capsule().fill(.black.opacity(0.5)).frame(width: 2, height: 14))
            .contentShape(Rectangle().inset(by: -6))
    }

    private func drag(_ width: CGFloat, _ set: @escaping (Double) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("trim"))
            .onChanged { value in set(Double(value.location.x / max(width, 1))) }
            .onEnded { _ in onCommit() }
    }
}
