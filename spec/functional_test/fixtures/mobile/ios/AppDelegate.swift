import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    private let stateMachine = AppStateMachine()

    // Multi-line (SwiftLint-folded) signature — the Kickstarter shape:
    // `func application(` and the `open url:` discriminator land on
    // different lines, and the body brace is several lines below.
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        routeOpenURL(url)
        stateMachine.handle(.openURL(url))
        return true
    }

    private func routeOpenURL(_ url: URL) {
        if !UIApplication.shared.canOpenURL(url) { return }
        print(url)
        switch url.host {
        case "debug":
            break
        default:
            break
        }
        logOpen(url.absoluteString)
    }
}
