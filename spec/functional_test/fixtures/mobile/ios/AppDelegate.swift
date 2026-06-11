import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    // Multi-line (SwiftLint-folded) signature — the Kickstarter shape:
    // `func application(` and the `open url:` discriminator land on
    // different lines, and the body brace is several lines below.
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        routeOpenURL(url)
        return true
    }

    private func routeOpenURL(_ url: URL) {
        logOpen(url.absoluteString)
    }
}
