require "../../func_spec.cr"

# Request reads the Next.js analyzer takes params from:
#   * App Router: Next 15's `await headers()` / `(await cookies()).get`,
#     `request.cookies.get`, a `searchParams` alias and `formData.getAll`.
expected_endpoints = [
  Endpoint.new("/api/webhook", "POST", [
    Param.new("stripe-signature", "", "header"),
    Param.new("idempotency-key", "", "header"),
    Param.new("theme", "", "cookie"),
    Param.new("session", "", "cookie"),
    Param.new("dryRun", "", "query"),
    Param.new("tags", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/javascript/nextjs_request_readers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
