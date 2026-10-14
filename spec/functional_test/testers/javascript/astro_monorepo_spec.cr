require "../../func_spec.cr"

# The Next.js app beside the Astro one also keeps `src/pages/`; its
# `api/hello.ts` and `about.md` are not Astro routes.
expected_endpoints = [
  Endpoint.new("/", "GET"),
]

FunctionalTester.new("fixtures/javascript/astro_monorepo/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("js_astro"),
}).perform_tests
