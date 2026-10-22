import Foundation

enum FeatureHost: String {
    case settings
    case profilePage = "profile"
}

func route(_ url: URL) {
    if url.host == FeatureHost.settings.rawValue {
        openSettings()
    }
}

func openSettings() {
    // ex) myapp://legacy/debug
    let legacyDebugURL = "myapp://legacy/debug"
    print(legacyDebugURL)
}
