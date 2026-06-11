import UIKit

final class FakeAppDelegateTests {
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        TestOnlyDeepLinkHandler.run(url)
        return true
    }
}
