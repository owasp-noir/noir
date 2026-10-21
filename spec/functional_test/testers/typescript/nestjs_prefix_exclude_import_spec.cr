require "../../func_spec.cr"

# `app.setGlobalPrefix('api', { exclude: excludePaths })` where the array is
# exported from another file through a tsconfig path alias (`src/constants.js`
# for `src/constants.ts`), as immich does. Excluded routes stay at the root;
# a `{ path, method }` entry excludes only that verb, and a commented-out
# entry excludes nothing.
expected_endpoints = [
  Endpoint.new("/.well-known/app", "GET"),
  Endpoint.new("/custom.css", "GET"),
  Endpoint.new("/api/custom.css", "POST"),
  Endpoint.new("/api/version", "GET"),
]

FunctionalTester.new("fixtures/typescript/nestjs_prefix_exclude_import/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
