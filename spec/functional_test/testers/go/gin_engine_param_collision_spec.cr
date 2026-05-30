require "../../func_spec.cr"

# Regression: a handler file reuses the variable name `r` as a *local*
# group (`r := v1.Group("/sysjob")`), while the engine entrypoint uses
# `r` as the `*gin.Engine` root (`v1 := r.Group("/api/v1")`). The flat
# per-package group map used to conflate the two, leaking `/sysjob` onto
# `v1` and polluting every route as `/sysjob/api/v1/...`. Root engine
# names are now excluded from the cross-file group map, so each file
# resolves its own `r` locally and the prefixes stay correct.
expected_endpoints = [
  Endpoint.new("/api/v1/sysjob/list", "GET"),
  Endpoint.new("/api/v1/sysjob/create", "POST"),
  Endpoint.new("/api/v1/job/start", "GET"),
]

FunctionalTester.new("fixtures/go/gin_engine_param_collision/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
