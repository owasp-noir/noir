require "../../func_spec.cr"

# `--only-endpoints` / `--exclude-endpoints` on a mixed code base: a click
# CLI next to a Flask app (which carries a `cli://app` command of its own).
# The CLI half is what #3471 wanted gone from the report.
mixed_bases = YAML::Any.new([
  YAML::Any.new("./spec/functional_test/fixtures/python/cli_click"),
  YAML::Any.new("./spec/functional_test/fixtures/python/flask"),
])

# Every CLI command and the `/sign*` routes dropped; the rest of Flask stays.
excluded = [
  Endpoint.new("/cookie", "GET"),
  Endpoint.new("/login", "POST"),
  Endpoint.new("/create_record", "PUT"),
  Endpoint.new("/delete_record", "DELETE"),
  Endpoint.new("/get_ip", "GET"),
  Endpoint.new("/update_record", "POST"),
  Endpoint.new("/search", "QUERY"),
  Endpoint.new("/lookup", "GET"),
  Endpoint.new("/lookup", "QUERY"),
  Endpoint.new("/", "GET"),
]

FunctionalTester.new("fixtures/python/flask/", {
  :techs     => 2,
  :endpoints => excluded.size,
}, excluded, {
  "base"              => mixed_bases,
  "exclude_endpoints" => YAML::Any.new([YAML::Any.new("protocol:cli"), YAML::Any.new("/sign*")]),
}).perform_tests

# `url:` matches the route, not the `-u`-joined URL, so `/*_record` keeps
# the record routes under a target too; `method:` and `url:` in one term
# must both hold, so only the DELETE is dropped.
only_records = [
  Endpoint.new("https://target.example/create_record", "PUT"),
  Endpoint.new("https://target.example/update_record", "POST"),
]

FunctionalTester.new("fixtures/python/flask/", {
  :techs     => 2,
  :endpoints => only_records.size,
}, only_records, {
  "base"              => mixed_bases,
  "url"               => YAML::Any.new("https://target.example"),
  "only_endpoints"    => YAML::Any.new([YAML::Any.new("/*_record")]),
  "exclude_endpoints" => YAML::Any.new([YAML::Any.new("method:DELETE url:/delete*")]),
}).perform_tests
