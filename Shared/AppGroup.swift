import ConvetaKit
import Foundation

/// The app group the app and its Finder extension share. Its id comes from Info.plist,
/// where the build fills in the team prefix, so no target hard-codes it.
enum AppGroup {
    static var identifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "ConvetaAppGroup") as? String
    }

    static var handoffs: HandoffStore { HandoffStore(suiteName: identifier) }
}
