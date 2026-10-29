require "../../func_spec.cr"

# A handler argument named by a `dependencies = {...: Provide(...)}` key is
# injected, not read from the request; `data` is the request body, so its
# type's fields are the params (form fields for a URL-encoded `Body`, the
# type imported from another module).
FunctionalTester.new("fixtures/python/litestar_di_params/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/api/access/forgot-password", "POST", [Param.new("email", "", "json")]),
  Endpoint.new("/api/access/login", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
  ]),
]).perform_tests
