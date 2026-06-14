require "../../func_spec.cr"

# Mautic registers routes in per-bundle `Config/config.php` arrays grouped by
# main/public/api. The `api` group is mounted under `/api`; verbs come from the
# optional `'method'` key (`'GET|POST'`, pipe-separated, default GET); path
# params are `{brace}`-style.
expected_endpoints = [
  Endpoint.new("/test", "GET"),
  Endpoint.new("/test/{objectId}", "POST", [Param.new("objectId", "", "path")]),
  Endpoint.new("/public/ping", "GET"),
  Endpoint.new("/api/widgets/{dir}", "GET", [Param.new("dir", "", "path")]),
  Endpoint.new("/api/widgets/new", "GET"),
  Endpoint.new("/api/widgets/new", "POST"),
]

FunctionalTester.new("fixtures/php/mautic/", {
  :techs     => 1,
  :endpoints => 6,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("php_mautic"),
}).perform_tests
