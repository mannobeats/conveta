import ConvetaKit
import FinderSync
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Finder", systemImage: "cursorarrow.click.2") { FinderSettings() }
            Tab("Downloads", systemImage: "arrow.down.circle") { DownloadSettings() }
            // Folder permissions only matter when the app runs sandboxed.
            if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil {
                Tab("Folders", systemImage: "lock.shield") { FolderSettings() }
            }
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
            Section {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { Updates.shared.updater.automaticallyChecksForUpdates },
                    set: { Updates.shared.updater.automaticallyChecksForUpdates = $0 }))
                Toggle("Download and install updates in the background", isOn: Binding(
                    get: { Updates.shared.updater.automaticallyDownloadsUpdates },
                    set: { Updates.shared.updater.automaticallyDownloadsUpdates = $0 }))
            } header: {
                Text("Updates")
            } footer: {
                Text("Conveta \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · Free and open source")
                    .foregroundStyle(.secondary)
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
                    Text("Select files on your Mac, right-click, and choose Convert with Conveta → MP4, JPEG, and more.")
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
                    Text("On every disk")
                    Text("Right-click files on any drive for Convert to MP3, MP4, JPEG or PNG with Conveta, or Add to Conveta. Choose which appear in System Settings → Keyboard → Keyboard Shortcuts → Services.")
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            extensionEnabled = FIFinderSyncController.isExtensionEnabled
        }
    }
}

private struct DownloadSettings: View {
    @Environment(AppState.self) private var state
    @State private var isUpdating = false

    private let browsers: [(id: String, name: String)] = [
        ("safari", "Safari"), ("chrome", "Chrome"), ("firefox", "Firefox"), ("brave", "Brave"),
        ("edge", "Edge"), ("arc", "Arc"), ("vivaldi", "Vivaldi"), ("opera", "Opera"),
    ]

    var body: some View {
        @Bindable var preferences = state.preferences
        let downloader = state.downloader
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        if isUpdating || downloader.status == .installing { ProgressView().controlSize(.small) }
                        Button(downloader.version == nil ? "Install" : "Check for Update") {
                            isUpdating = true
                            Task {
                                if downloader.version == nil { try? await downloader.install() } else { await downloader.updateIfStale(force: true) }
                                isUpdating = false
                            }
                        }
                        .disabled(isUpdating || downloader.status == .installing)
                    }
                } label: {
                    Text("Download engine")
                    Text(engineDescription(downloader))
                }
            } footer: {
                Text("Downloads use yt-dlp, an open-source engine for YouTube, Instagram, TikTok, X, Vimeo and over a thousand other sites. Conveta installs it from its official GitHub release, verifies its checksum, and updates it every few days, because sites change often.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Subtitles", selection: $preferences.subtitles.mode) {
                    ForEach(SubtitleOptions.Mode.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Language", selection: $preferences.subtitles.language) {
                    ForEach(languages, id: \.self) { code in
                        Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code)
                    }
                }
                .disabled(preferences.subtitles.mode == .off)
                Toggle("Use automatic captions when there are none", isOn: $preferences.subtitles.includeAutomatic)
                    .disabled(preferences.subtitles.mode == .off)
            } header: {
                Text("Subtitles")
            } footer: {
                Text("Subtitles are embedded as a track you can turn on in QuickTime, or saved beside the video as an .srt file.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Use sign-ins from", selection: Binding(get: { preferences.cookiesBrowser ?? "" }, set: { preferences.cookiesBrowser = $0.isEmpty ? nil : $0 })) {
                    Text("No Browser").tag("")
                    Divider()
                    ForEach(browsers, id: \.id) { Text($0.name).tag($0.id) }
                }
            } footer: {
                Text("Some posts (private Instagram accounts, age-restricted videos) need you to be signed in. Choose the browser you’re signed in with, and Conveta borrows its cookies for those downloads only. Safari needs Full Disk Access for Conveta.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Download only videos you own or have permission to use, and respect each site’s terms.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var languages: [String] {
        let common = ["en", "es", "fr", "de", "it", "pt", "nl", "ru", "ja", "ko", "zh", "ar", "hi", "tr", "pl", "sv"]
        let mine = Locale.preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        var seen = Set<String>()
        return (mine + common).filter { seen.insert($0).inserted }
    }

    private func engineDescription(_ downloader: Downloader) -> String {
        switch downloader.status {
        case .notInstalled: return "Installs the first time you add a link (about 35 MB)."
        case .installing: return "Installing…"
        case .failed(let reason): return reason
        case .ready(let version):
            let checked = downloader.lastChecked.map { " · checked \($0.formatted(.relative(presentation: .named)))" } ?? ""
            return "yt-dlp \(version)\(checked)"
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
