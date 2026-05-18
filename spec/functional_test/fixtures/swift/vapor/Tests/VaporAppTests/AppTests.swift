// Regression guard: Swift Package Manager parks XCTest sources under
// `Tests/<TargetName>Tests/`. Routes registered inside these test
// files exercise the router but never serve real traffic. None of
// the URLs below should appear in the fixture's expected-endpoints
// list.
import Vapor
import XCTest

final class AppTests: XCTestCase {
    func testRoutes() throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        app.get("should-not-appear-tests-dir") { _ in "" }
        app.post("should-not-appear-tests-dir-post") { _ in "" }
    }
}
