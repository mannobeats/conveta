import Combine
import ConvetaKit
import Observation
import SwiftUI

/// A mirror of the queue state the menus need. SwiftUI `Commands` don't follow `@Observable`
/// models reliably, so this `ObservableObject` is updated whenever the queue changes.
final class MenuState: ObservableObject {
    static let shared = MenuState()

    @Published private(set) var canConvert = false
    @Published private(set) var isRunning = false
    @Published private(set) var hasSelection = false
    @Published private(set) var canRevealOutput = false
    @Published private(set) var canClear = false

    func track(_ queue: ConversionQueue) {
        withObservationTracking {
            let selected = queue.selectedJobs
            set(\.canConvert, queue.canConvert)
            set(\.isRunning, queue.isRunning)
            set(\.hasSelection, !selected.isEmpty)
            set(\.canRevealOutput, selected.contains { $0.output != nil })
            set(\.canClear, queue.jobs.contains { $0.state.isFinished || $0.state == .cancelled || $0.state.isUnsupported })
        } onChange: { [weak self] in
            Task { @MainActor in self?.track(queue) }
        }
    }

    private func set(_ key: ReferenceWritableKeyPath<MenuState, Bool>, _ value: Bool) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }
}

struct AppCommands: Commands {
    let state: AppState
    @ObservedObject var menu: MenuState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Files…") { state.isImporterPresented = true }
                .keyboardShortcut("o")
            Button("Download from Link…") { state.isLinkSheetPresented = true }
                .keyboardShortcut("l")
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button(menu.hasSelection ? "Convert Selected" : "Convert All") { state.queue.convertSelectionOrAll() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!menu.canConvert)
            Button("Stop Converting") { state.queue.cancelAll() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!menu.isRunning)
            Divider()
            Button("Show Converted File in Finder") { state.queue.revealOutputs(of: state.queue.selection) }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!menu.canRevealOutput)
            Button("Show Original") { state.queue.revealSources(of: state.queue.selection) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!menu.hasSelection)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Remove from List") { state.queue.remove(state.queue.selection) }
                .disabled(!menu.hasSelection)
            Button("Clear Finished") { state.queue.clearFinished() }
                .keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(!menu.canClear)
        }
    }
}
