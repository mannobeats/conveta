import ConvetaKit
import SwiftUI

/// What the window shows before any file is added: one large drop target, and a quiet hint
/// that Finder's right-click menu works too.
struct EmptyDropView: View {
    let isTargeted: Bool
    let choose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(spacing: 22) {
                KindCluster(isTargeted: isTargeted)
                VStack(spacing: 6) {
                    Text(isTargeted ? "Drop to Add" : "Drop Files to Convert")
                        .font(.title2.weight(.semibold))
                        .contentTransition(.opacity)
                    Text("Videos, audio, images and PDFs. One file or a thousand.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Button("Choose Files…", action: choose)
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .keyboardShortcut("o", modifiers: .command)
            }
            .padding(40)
            .frame(maxWidth: 520)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                                  style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: isTargeted ? [] : [7, 6]))
                    .background(isTargeted ? Color.accentColor.opacity(0.06) : .clear,
                                in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .scaleEffect(isTargeted && !reduceMotion ? 1.015 : 1)
            .animation(Theme.motion, value: isTargeted)
            .padding(.horizontal, 32)
            Spacer(minLength: 24)
            finderHint
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var finderHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "cursorarrow.click.2")
            Text("You can also right-click files in Finder and choose Convert with Conveta.")
            Button("Set Up…") { openSettings() }
                .buttonStyle(.link)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// Four kind badges fanned out; they lift apart while files hover over the window.
private struct KindCluster: View {
    let isTargeted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let kinds: [MediaKind] = [.image, .video, .audio, .document]

    var body: some View {
        ZStack {
            ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                let offset = CGFloat(index) - 1.5
                KindBadge(kind: kind, size: 58)
                    .shadow(color: Theme.color(for: kind).opacity(0.35), radius: 10, y: 5)
                    .rotationEffect(.degrees(Double(offset) * (isTargeted ? 12 : 8)))
                    .offset(x: offset * (isTargeted ? 52 : 40), y: abs(offset) * (isTargeted ? 10 : 6) - (isTargeted && !reduceMotion ? 6 : 0))
                    .zIndex(index == 1 ? 3 : Double(index))
            }
        }
        .frame(height: 96)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2), value: isTargeted)
    }
}
