require "../../func_spec.cr"

# `new Elysia().get(...).handle(new Request(...))` in `test/index.test.ts`
# (a `.test.` name) and in `test/helpers.ts` (a plain name, but a describe
# suite) is driven in-process, never served. `src/page.ts` imports react
# beside Elysia and keeps its route.
expected_endpoints = [
  Endpoint.new("/elysia-real", "GET"),
  Endpoint.new("/elysia-page", "GET"),
]

FunctionalTester.new("fixtures/javascript/elysia_test_suite/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
