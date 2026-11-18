import AppKit
import ConvetaKit
@preconcurrency import UserNotifications

/// What happens when a batch finishes: a sound, a notification when Conveta is in the background,
/// and optionally the converted files selected in Finder.
final class CompletionFeedback {
    func batchFinished(_ jobs: [ConversionJob], preferences: Preferences) {
        let done = jobs.filter { $0.state == .done }
        let failed = jobs.filter { if case .failed = $0.state { true } else { false } }
        guard !done.isEmpty || !failed.isEmpty else { return }

        if preferences.playSoundWhenDone {
            NSSound(named: failed.isEmpty ? "Glass" : "Basso")?.play()
        }
        if preferences.revealWhenDone, !done.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(done.compactMap(\.output))
        }
        if preferences.notifyWhenDone, !NSApp.isActive {
            Self.notify(title: Self.title(done: done.count, failed: failed.count), body: Self.body(done))
        }
    }

    static func title(done: Int, failed: Int) -> String {
        switch (done, failed) {
        case (_, 0): done == 1 ? "1 file converted" : "\(done) files converted"
        case (0, _): failed == 1 ? "1 file couldn’t be converted" : "\(failed) files couldn’t be converted"
        default: "\(done) converted, \(failed) failed"
        }
    }

    private static func body(_ done: [ConversionJob]) -> String {
        let saved = done.reduce(Int64(0)) { $0 + (($1.info?.fileSize ?? 0) - ($1.outputSize ?? 0)) }
        guard saved > 0 else { return done.first.map { "Saved as “\($0.output?.lastPathComponent ?? $0.name)”." } ?? "" }
        return "\(ByteCountFormatter.string(fromByteCount: saved, countStyle: .file)) smaller in total."
    }

    private static func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
