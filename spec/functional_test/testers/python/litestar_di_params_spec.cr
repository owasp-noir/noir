require "../../func_spec.cr"

# A handler argument named by a `dependencies = {...: Provide(...)}` key is
# injected, not read from the request; `data` is the request body, so its
# type's fields are the params (form fields for a URL-encoded `Body`, the
# type imported from another module). A key declared in one file (admin's
# `page`) does not hide a same-named query param elsewhere, a `key=` on a
# later line of a multi-line `dependencies = helper(...)` counts, and a
# model with a base this pass does not follow keeps the plain `data` param.
FunctionalTester.new("fixtures/python/litestar_di_params/", {
  :techs     => 1,
  :endpoints => 5,
}, [
  Endpoint.new("/api/admin/stats", "GET"),
  Endpoint.new("/search", "GET", [Param.new("q", "", "query"), Param.new("page", "", "query")]),
  Endpoint.new("/api/access/signup", "POST", [Param.new("data", "", "json")]),
  Endpoint.new("/api/access/forgot-password", "POST", [Param.new("email", "", "json")]),
  Endpoint.new("/api/access/login", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
  ]),
]).perform_tests
