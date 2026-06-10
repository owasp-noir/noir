import UIKit
import WebKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var webView: WKWebView?

    // Custom URL scheme dispatch (myapp:// , myapp-alt://)
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let redirect = components?.queryItems?.first(where: { $0.name == "redirect" })?.value
        handleDeepLink(url)
        if let redirect = redirect, let target = URL(string: redirect) {
            webView?.load(URLRequest(url: target))
        }
    }

    // Universal link dispatch (https://...)
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let url = userActivity.webpageURL else { return }
        routeUniversalLink(url)
    }

    private func handleDeepLink(_ url: URL) {
        logEvent(url.absoluteString)
    }

    private func routeUniversalLink(_ url: URL) {
        openProfile(url.lastPathComponent)
    }
}
