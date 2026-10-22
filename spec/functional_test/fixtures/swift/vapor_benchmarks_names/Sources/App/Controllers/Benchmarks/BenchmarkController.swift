import Vapor

// A benchmark-results API: the directory is named Benchmarks, but it is
// application source, not a package-benchmark target.
struct BenchmarkController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("benchmarks") { req in
            "results"
        }
    }
}
