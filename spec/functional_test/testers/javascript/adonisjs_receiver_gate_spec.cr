require "../../func_spec.cr"

# The AdonisJS walker must gate its verb/`on` dispatch on the chain ROOT
# receiver being `router`/`Route`. `env.get(...)`, `session.get(...)` and a
# Lucid `query()...delete('*')` are shaped like registrations but are not
# routes, so only the three real router registrations survive — and
# `router.on('/path')` (always GET) is recovered.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/terms", "GET"),
]

FunctionalTester.new("fixtures/javascript/adonisjs_receiver_gate/", {
  :techs     => 1,
  :endpoints => 3,
}, expected_endpoints).perform_tests
