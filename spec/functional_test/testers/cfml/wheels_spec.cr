require "../../func_spec.cr"

# Wheels routes are one fluent `mapper()` chain. It is order-dependent,
# so the analyzer walks it with a prefix stack: `scope`, a nested
# `resources` and `member` each push a segment and `end()` pops it.
expected_endpoints = [
  # `pattern` is optional and falls back to the route name.
  Endpoint.new("/login", "GET"),
  Endpoint.new("/login", "POST"),

  # `[token]` is Wheels' placeholder spelling, not `:token`.
  Endpoint.new("/verify/:token", "GET", [Param.new("token", "", "path")]),

  # Plural resources: full REST set, update answering PUT and PATCH.
  Endpoint.new("/tweets", "GET"),
  Endpoint.new("/tweets", "POST"),
  Endpoint.new("/tweets/new", "GET"),
  Endpoint.new("/tweets/:key", "GET", [Param.new("key", "", "path")]),
  Endpoint.new("/tweets/:key/edit", "GET", [Param.new("key", "", "path")]),
  Endpoint.new("/tweets/:key", "PUT", [Param.new("key", "", "path")]),
  Endpoint.new("/tweets/:key", "PATCH", [Param.new("key", "", "path")]),
  Endpoint.new("/tweets/:key", "DELETE", [Param.new("key", "", "path")]),

  # Singular resource: no index and no key segment, narrowed by `only`.
  Endpoint.new("/account", "GET"),
  Endpoint.new("/account/edit", "GET"),
  Endpoint.new("/account", "PUT"),
  Endpoint.new("/account", "PATCH"),

  # Everything inside the scope is prefixed with its path.
  Endpoint.new("/admin/users", "GET"),
  Endpoint.new("/admin/users", "POST"),
  Endpoint.new("/admin/users/new", "GET"),
  Endpoint.new("/admin/users/:key", "GET", [Param.new("key", "", "path")]),
  Endpoint.new("/admin/users/:key/edit", "GET", [Param.new("key", "", "path")]),
  Endpoint.new("/admin/users/:key", "PUT", [Param.new("key", "", "path")]),
  Endpoint.new("/admin/users/:key", "PATCH", [Param.new("key", "", "path")]),
  Endpoint.new("/admin/users/:key", "DELETE", [Param.new("key", "", "path")]),

  # `nested=true` scopes the child resource under the parent's key.
  Endpoint.new("/admin/users/:userKey/permissions", "GET", [Param.new("userKey", "", "path")]),
  Endpoint.new("/admin/users/:userKey/permissions", "POST", [Param.new("userKey", "", "path")]),

  Endpoint.new("/admin/users/:userKey/permissions/:key", "GET", [Param.new("userKey", "", "path"), Param.new("key", "", "path")]),

  # `member()` routes act on the existing record.
  Endpoint.new("/admin/users/:key/assume", "POST", [Param.new("key", "", "path")]),
  Endpoint.new("/admin/users/:key/reset", "PUT", [Param.new("key", "", "path")]),

  # `except` drops actions; the scope prefix still applies after the
  # nested block closes.
  Endpoint.new("/admin/roles", "GET"),
  Endpoint.new("/admin/roles", "POST"),
  Endpoint.new("/admin/roles/:key", "PUT", [Param.new("key", "", "path")]),
  Endpoint.new("/admin/roles/:key", "PATCH", [Param.new("key", "", "path")]),
  Endpoint.new("/admin/roles/:key", "DELETE", [Param.new("key", "", "path")]),

  # `wildcard()` maps every controller/action pair and is deliberately
  # not expanded, so only `root` remains at the top level.
  Endpoint.new("/", "GET"),
]

FunctionalTester.new("fixtures/cfml/wheels/", {
  :techs     => 2, # Detection still sees cfml_wheels and cfml_pure
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
