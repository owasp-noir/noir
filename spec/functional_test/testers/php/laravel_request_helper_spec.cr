require "../../func_spec.cr"

# Input read through the `request()` helper (`request('x')`, `request([...])`,
# `request()->x`), the `Request` facade imported under an alias, and the
# accessors `str`, `collect`, `hasAny`, `whenHas`, `hasHeader`, `json` and
# `bearerToken` (the `Authorization` header).
expected_endpoints = [
  Endpoint.new("/control", "GET", [Param.new("control-in", "", "query")]),
  Endpoint.new("/posts", "GET", [
    Param.new("search", "", "query"),
    Param.new("category", "", "query"),
    Param.new("sort", "", "query"),
    Param.new("page_size", "", "query"),
    Param.new("tag", "", "query"),
  ]),
  Endpoint.new("/posts", "POST", [
    Param.new("title", "", "form"),
    Param.new("body", "", "form"),
    Param.new("slug", "", "form"),
  ]),
  Endpoint.new("/token", "POST", [
    Param.new("name", "", "form"),
    Param.new("tags", "", "form"),
    Param.new("x1", "", "form"),
    Param.new("x2", "", "form"),
    Param.new("promo", "", "form"),
    Param.new("meta.id", "", "form"),
    Param.new("X-Tenant", "", "header"),
    Param.new("Authorization", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/php/laravel_request_helper/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
