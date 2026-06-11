import UIKit

enum AppAction {
    case openURL(URL)
}

final class AppStateMachine {
    private let coordinator = DeepLinkCoordinator()

    func handle(_ action: AppAction) {
        switch action {
        case .openURL(let url):
            openURL(url)
        }
    }

    private func openURL(_ url: URL) {
        Logger.sync.debug("open \(url)")
        guard coordinator.shouldProcessDeepLink(url) else { return }
        NotificationCenter.default.post(name: Notification.Name("DeepLink"), object: nil)
        coordinator.handleURL(url)
    }
}

final class DeepLinkCoordinator {
    func shouldProcessDeepLink(_ url: URL) -> Bool {
        true
    }

    func handleURL(_ url: URL) {
        renderDeepLink(url.absoluteString)
    }
}
