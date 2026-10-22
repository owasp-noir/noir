import Benchmark
import Vapor

// package-benchmark keeps its targets under Benchmarks/. The routes below
// exist only for the benchmark workload, not for the app.
func configureWorkloads(_ app: Application) {
    app.get("bench", "status") { req in
        "ok"
    }
}
