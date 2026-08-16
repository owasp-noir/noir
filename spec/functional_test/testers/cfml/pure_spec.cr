require "../../func_spec.cr"

# A `remote` CFC method is reachable as both GET and POST, so each one
# yields two endpoints; `.cfm` pages yield GET plus POST when the page
# reads the `form` scope.
expected_endpoints = [
  # Tag syntax: <cffunction access="remote"> + <cfargument>
  Endpoint.new("/components/RemoteService.cfc?method=logMessage", "GET", [
    Param.new("instanceName", "", "query"),
    Param.new("message", "", "query"),
  ]),
  Endpoint.new("/components/RemoteService.cfc?method=logMessage", "POST", [
    Param.new("instanceName", "", "form"),
    Param.new("message", "", "form"),
  ]),
  # `access` is not always the second attribute, and <cfargument> may span lines
  Endpoint.new("/components/RemoteService.cfc?method=getQueue", "GET", [
    Param.new("instanceName", "", "query"),
  ]),
  Endpoint.new("/components/RemoteService.cfc?method=getQueue", "POST", [
    Param.new("instanceName", "", "form"),
  ]),

  # Script syntax: `remote` as a leading modifier
  Endpoint.new("/api/Proxy.cfc?method=echo", "GET", [
    Param.new("text", "", "query"),
  ]),
  Endpoint.new("/api/Proxy.cfc?method=echo", "POST", [
    Param.new("text", "", "form"),
  ]),
  # Script syntax: `access="remote"` as a trailing attribute
  Endpoint.new("/api/Proxy.cfc?method=ping", "GET"),
  Endpoint.new("/api/Proxy.cfc?method=ping", "POST"),
  # Typed and defaulted script arguments
  Endpoint.new("/api/Proxy.cfc?method=search", "GET", [
    Param.new("term", "", "query"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/api/Proxy.cfc?method=search", "POST", [
    Param.new("term", "", "form"),
    Param.new("page", "", "form"),
  ]),

  # A CFML string has no backslash escape, so a default value ending in one
  # (a Windows path) closes at the next quote: the argument list still ends
  # at the `)` on the same line, and `mask` is its own argument.
  Endpoint.new("/api/Files.cfc?method=listUploads", "GET", [
    Param.new("folder", "", "query"),
    Param.new("mask", "", "query"),
  ]),
  Endpoint.new("/api/Files.cfc?method=listUploads", "POST", [
    Param.new("folder", "", "form"),
    Param.new("mask", "", "form"),
  ]),
  # A quote inside a string is written by doubling it, and the comma inside
  # that literal does not separate arguments.
  Endpoint.new("/api/Files.cfc?method=describe", "GET", [
    Param.new("label", "", "query"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/api/Files.cfc?method=describe", "POST", [
    Param.new("label", "", "form"),
    Param.new("page", "", "form"),
  ]),

  # .cfm pages are file-path routed
  Endpoint.new("/index.cfm", "GET", [
    Param.new("view", "", "query"),
    Param.new("lang", "", "query"),
  ]),
  Endpoint.new("/search.cfm", "GET", [
    Param.new("q", "", "query"),
    Param.new("category", "", "query"),
  ]),
  Endpoint.new("/account/login.cfm", "GET", [
    Param.new("session_id", "", "cookie"),
    Param.new("user-agent", "", "header"),
  ]),
  Endpoint.new("/account/login.cfm", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
    Param.new("session_id", "", "cookie"),
  ]),

  # Client-side JS that manipulates a DOM `form` must not register as
  # CFML form-scope access (no `action`/`submit` params, and no POST
  # variant), while `#url.days#` interpolated into that same script
  # still counts as a real request read.
  Endpoint.new("/report.cfm", "GET", [
    Param.new("range", "", "query"),
    Param.new("days", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/cfml/pure/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
