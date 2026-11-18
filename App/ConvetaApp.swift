import ConvetaKit
import SwiftUI

@main
struct ConvetaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState.shared
    @ObservedObject private var menu = MenuState.shared

    var body: some Scene {
        Window("Conveta", id: "main") {
            MainWindow()
                .environment(state)
        }
        .defaultSize(width: 980, height: 620)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(state: state, menu: menu)
            UpdateCommands()
            InspectorCommands()
        }

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}
