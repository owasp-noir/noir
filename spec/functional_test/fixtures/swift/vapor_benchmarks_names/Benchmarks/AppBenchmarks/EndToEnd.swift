import Benchmark
import Vapor

// package-benchmark keeps its targets under the package root's Benchmarks/.
func configureWorkloads(_ app: Application) {
    app.get("bench", "status") { req in
        "ok"
    }
}
