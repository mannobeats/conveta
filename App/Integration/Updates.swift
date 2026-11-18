import Combine
import Sparkle
import SwiftUI

/// Sparkle, the standard updater for Mac apps shipped outside the App Store. Releases are signed
/// with an EdDSA key held by the release pipeline; the public half is `SUPublicEDKey` in Info.plist.
final class Updates: ObservableObject {
    static let shared = Updates()

    let controller = SPUStandardUpdaterController(startingUpdater: !SelfTest.isRequested, updaterDelegate: nil, userDriverDelegate: nil)
    @Published private(set) var canCheck = false
    private var observation: AnyCancellable?

    private init() {
        observation = controller.updater.publisher(for: \.canCheckForUpdates).sink { [weak self] value in
            self?.canCheck = value
        }
    }

    var updater: SPUUpdater { controller.updater }

    func check() { controller.checkForUpdates(nil) }
}

/// "Check for Updates…" under the app menu, where Mac apps put it.
struct UpdateCommands: Commands {
    @ObservedObject var updates = Updates.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updates.check() }
                .disabled(!updates.canCheck)
        }
    }
}
