require "../../func_spec.cr"

# Classic ASP is file-path routed, so each requestable `.asp` becomes an
# endpoint. A page is also POST when it reads the form collection or a
# bare `Request(...)` that could resolve to it.
expected_endpoints = [
  # `<%@ %>` directive skipped; commented-out reads and client-side
  # <script> are not server code, so `legacy_id` / `clientside` must not
  # appear. `Request.QueryString ("sort")` has a space before `(`.
  Endpoint.new("/default.asp", "GET", [
    Param.new("page", "", "query"),
    Param.new("sort", "", "query"),
  ]),
  # IIS default document also answers the bare directory URL.
  Endpoint.new("/", "GET", [
    Param.new("page", "", "query"),
    Param.new("sort", "", "query"),
  ]),

  # Cookies and `HTTP_*` server variables map to their own param types;
  # an apostrophe inside a VBScript string must not truncate the scan.
  Endpoint.new("/login.asp", "GET", [
    Param.new("session", "", "cookie"),
    Param.new("x-forwarded-for", "", "header"),
  ]),
  Endpoint.new("/login.asp", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
    Param.new("session", "", "cookie"),
  ]),

  # Bare `Request("q")` is ambiguous, so it lands on both methods.
  # `Request("prefix-" & userId)` is runtime-built and must be skipped,
  # and the `_` line continuation must not hide `page`.
  Endpoint.new("/admin/search.asp", "GET", [
    Param.new("q", "", "query"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/admin/search.asp", "POST", [
    Param.new("q", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/asp/classic/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
