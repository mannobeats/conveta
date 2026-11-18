import ConvetaKit
import FinderSync
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Finder", systemImage: "cursorarrow.click.2") { FinderSettings() }
            Tab("Folders", systemImage: "lock.shield") { FolderSettings() }
        }
        .scenePadding()
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var preferences = state.preferences
        Form {
            Section {
                Toggle("Start converting as soon as files are added", isOn: $preferences.startImmediately)
                Stepper(value: $preferences.parallelJobs, in: 1...8) {
                    LabeledContent("Files converted at once", value: "\(preferences.parallelJobs)")
                }
                .help("This Mac works best with \(Preferences.recommendedParallelJobs). More can be slower for video.")
            }
            Section("When Files Are Converted") {
                Toggle("Play a sound", isOn: $preferences.playSoundWhenDone)
                Toggle("Notify me when Conveta is in the background", isOn: $preferences.notifyWhenDone)
                Toggle("Show converted files in Finder", isOn: $preferences.revealWhenDone)
            }
            Section {
                LabeledContent("Format choices") {
                    Button("Reset to Defaults") { preferences.resetDefaults() }
                        .disabled(preferences.defaults.isEmpty)
                }
            } footer: {
                Text("Conveta remembers the last format and settings you chose for each kind of file.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct FinderSettings: View {
    @State private var extensionEnabled = FIFinderSyncController.isExtensionEnabled

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if extensionEnabled {
                        Label("On", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Turn On…") { FIFinderSyncController.showExtensionManagementInterface() }
                    }
                } label: {
                    Text("Right-click menu in Finder")
                    Text("Select files, right-click, and choose Convert with Conveta → MP4, JPEG, and more.")
                }
            } footer: {
                if !extensionEnabled {
                    Text("In System Settings, turn on Conveta under File Providers & Finder Extensions.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent {
                    Button("Open Shortcuts") { NSWorkspace.shared.open(URL(string: "shortcuts://")!) }
                } label: {
                    Text("Quick Actions and Shortcuts")
                    Text("Use the Convert Files action in Shortcuts, then turn on “Use as Quick Action” to add it to Finder.")
                }
                LabeledContent {
                    Text("Always on").foregroundStyle(.secondary)
                } label: {
                    Text("Services menu")
                    Text("“Add to Conveta” is in the Services menu of any app that has files selected.")
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            extensionEnabled = FIFinderSyncController.isExtensionEnabled
        }
    }
}

private struct FolderSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let access = state.access
        Form {
            Section {
                if access.grantedFolders.isEmpty {
                    Text("No folders yet. Conveta asks the first time it needs one.")
                        .foregroundStyle(.secondary)
                }
                ForEach(access.grantedFolders, id: \.self) { folder in
                    LabeledContent {
                        Button("Remove", systemImage: "minus.circle") { access.revoke(folder) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Stop allowing access to this folder")
                    } label: {
                        Label(folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent, systemImage: "folder")
                        Text(folder.path(percentEncoded: false)).truncationMode(.middle)
                    }
                }
            } header: {
                Text("Folders Conveta Can Use")
            } footer: {
                Text("macOS lets Conveta save next to your originals, and open files sent from Finder, only in folders you allow. Allowing your home folder covers everything inside it.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Allow a Folder…") {
                    access.requestAccess(to: FileManager.default.homeDirectoryForCurrentUser.realHome,
                                         reason: "Choose a folder Conveta may read from and save to. Your home folder covers every folder inside it.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

extension URL {
    /// In the sandbox the home directory points into the app container; this is the person's real home.
    var realHome: URL {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return self }
        return URL(filePath: String(cString: dir), directoryHint: .isDirectory)
    }
}
