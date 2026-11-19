require "../../func_spec.cr"

# `s.mux.HandleFunc(...)` on a struct field declared `*http.ServeMux` is a
# route; `w.jobs.Handle(...)` on a field of another type is not.
legacy = %w[GET POST PUT DELETE PATCH HEAD OPTIONS].map { |verb| Endpoint.new("/legacy", verb) }
expected_endpoints = [
  Endpoint.new("/api/users", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/users", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/api/health", "GET"),
] + legacy

FunctionalTester.new("fixtures/go/http_field_mux/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
