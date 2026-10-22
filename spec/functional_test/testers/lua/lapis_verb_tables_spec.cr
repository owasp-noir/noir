require "../../func_spec.cr"

fallback_methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]

expected_endpoints = [] of Endpoint

# A verb-keyed application table declares its whole method set: Lapis
# answers 405 for anything it does not name, so a single-verb table is a
# single endpoint, not a five-verb fan-out.
expected_endpoints << Endpoint.new("/cache", "DELETE")
expected_endpoints << Endpoint.new("/cache/:key", "GET", [Param.new("key", "", "path")])
expected_endpoints << Endpoint.new("/cache/:key", "DELETE", [Param.new("key", "", "path")])

# One handler bound to several verbs.
expected_endpoints << Endpoint.new("/shared", "GET")
expected_endpoints << Endpoint.new("/shared", "HEAD")

# Bracketed string keys are the same declaration.
expected_endpoints << Endpoint.new("/bracket-keys", "GET")
expected_endpoints << Endpoint.new("/bracket-keys", "OPTIONS")

# Descriptor form — the verbs live under a `methods` sub-table.
expected_endpoints << Endpoint.new("/clustering/data-planes", "GET")

# `respond_to({ ... })` names its verbs explicitly.
expected_endpoints << Endpoint.new("/wrapped", "GET")
expected_endpoints << Endpoint.new("/wrapped", "POST")

# Values that carry no method evidence keep the all-verbs fallback: a
# module reference, a filter-only table, a bare function, a named string
# handler.
fallback_methods.each { |m| expected_endpoints << Endpoint.new("/disabled", m) }
fallback_methods.each { |m| expected_endpoints << Endpoint.new("/fallback/filtered", m) }
fallback_methods.each { |m| expected_endpoints << Endpoint.new("/fallback/inline", m) }
fallback_methods.each { |m| expected_endpoints << Endpoint.new("/fallback/named", m) }

# `["/fallback/lookup"] = true` is a URL-keyed lookup table, not a route,
# and is deliberately absent from the expectations above.

FunctionalTester.new("fixtures/lua/lapis_verb_tables/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
