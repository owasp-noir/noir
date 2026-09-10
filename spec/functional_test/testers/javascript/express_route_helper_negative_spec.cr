require "../../func_spec.cr"

# The other side of the forwarding-helper pass: a function that forwards a
# caller-supplied path to a caller-supplied receiver is not automatically a
# route registration.
#
# `src/http-client.js` holds five such functions — including
# `request(client, method, url) { client[method](url, opts) }`, which is
# structurally identical to NodeBB's `setupApiRoute` — and
# `src/consumers.js` calls each of them with a literal HTTP verb and a
# literal path. Only `/healthz`, registered directly on an Express app,
# may come out.
#
# This is the guard against reopening the false-positive class an earlier
# audit found in NodeBB, where ~250 "endpoints" were HTTP client calls.

expected_endpoints = [
  Endpoint.new("/healthz", "GET"),
]

FunctionalTester.new("fixtures/javascript/express_route_helper_negative/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
