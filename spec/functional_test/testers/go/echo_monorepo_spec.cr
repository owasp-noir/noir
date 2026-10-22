require "../../func_spec.cr"

# The Go module sits two directories below the scan base, which is the
# ordinary monorepo shape. `resolve_public_dir_path` resolves a static
# route's disk path against the source file's own directory first — but
# gated that branch on `Dir.exists?`, so the single-file form
# (`e.File("/robots.txt", "static/robots.txt")`) never took it. It fell
# back to `base_path + "static/robots.txt"`, which only exists when the
# scan base happens to be the Go project root, and the route was lost.
# Directory statics were unaffected, which is why this fixture asserts
# both.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/public/hello.txt", "GET"),
  Endpoint.new("/robots.txt", "GET"),
]

FunctionalTester.new("fixtures/go/echo_monorepo/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
