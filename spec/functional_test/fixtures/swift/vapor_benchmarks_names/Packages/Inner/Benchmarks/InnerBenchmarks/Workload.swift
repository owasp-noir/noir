import Benchmark
import Vapor

// A nested package keeps its package-benchmark targets beside its own
// Package.swift.
func configureInnerWorkloads(_ app: Application) {
    app.get("inner-bench") { req in
        "ok"
    }
}
