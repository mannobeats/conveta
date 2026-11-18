import ConvetaKit
import SwiftUI

/// "Preset" row at the top of each kind's settings: apply a recipe, or save the current settings as one.
struct PresetMenu: View {
    @Environment(AppState.self) private var state
    let kind: MediaKind
    let current: ConversionSettings
    let update: SettingsUpdate
    @State private var isNaming = false
    @State private var name = ""

    var body: some View {
        let presets = state.presets.all.filter { $0.applies(to: kind) }
        let active = presets.first { $0.settings.format == current.format && $0.apply(to: current) == current }
        LabeledContent("Preset") {
            Menu(active?.name ?? "Custom") {
                let mine = presets.filter { !$0.isBuiltIn }
                if !mine.isEmpty {
                    Section("My Presets") { ForEach(mine) { item($0) } }
                }
                Section("Built In") { ForEach(presets.filter(\.isBuiltIn)) { item($0) } }
                Divider()
                Button("Save Current Settings as Preset…") { name = ""; isNaming = true }
                if let active, !active.isBuiltIn {
                    Button("Delete “\(active.name)”", role: .destructive) { state.presets.delete(active.id) }
                }
            }
            .menuStyle(.button)
            .fixedSize()
        }
        .sheet(isPresented: $isNaming) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Save as Preset").font(.headline)
                Text("Saves \(current.format.displayName) with these settings. It shows up here, in Finder’s right-click menu and in Shortcuts.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Name", text: $name, prompt: Text("For example, Client Delivery"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { isNaming = false }.keyboardShortcut(.cancelAction)
                    Button("Save", action: save).keyboardShortcut(.defaultAction)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 360)
        }
    }

    private func item(_ preset: Preset) -> some View {
        Button {
            withAnimation(Theme.motion) { update { $0 = preset.apply(to: $0) } }
        } label: {
            Text(preset.name)
            Text(preset.summary)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var settings = current
        settings.trim = nil
        settings.downloadHeight = nil
        let summary = [settings.format.displayName, settings.video.targetMegabytes.map { "≤ \($0) MB" }].compactMap { $0 }.joined(separator: ", ")
        state.presets.save(Preset(name: trimmed, summary: summary, settings: settings))
        isNaming = false
    }
}

/// Presets the app and the Finder extension share, observable so menus refresh when one is saved.
@Observable
final class PresetLibrary {
    private(set) var all: [Preset]
    @ObservationIgnored private let store: PresetStore

    init(store: PresetStore) {
        self.store = store
        all = store.all
    }

    func save(_ preset: Preset) { store.save(preset); all = store.all }
    func delete(_ id: String) { store.delete(id); all = store.all }
    func preset(id: String) -> Preset? { all.first { $0.id == id } }
}
