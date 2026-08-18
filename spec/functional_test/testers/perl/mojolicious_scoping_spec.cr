require "../../func_spec.cr"

# Two Perl services in one checkout: a Dancer2 app and a Mojolicious app.
#
# `perl_mojolicious` used to claim both, because `PerlEngine` handed every
# `.pm` to every Perl analyzer and `FULL_VERB_RE` treated *any*
# `->get('literal')` as a route. That combination reported Dancer2's
# `query_parameters->get('page')` reads as `GET /page` (and its real routes
# a second time, prefix-stripped), and inside the Mojolicious app itself it
# reported `$cache->get("session_timeout")` as `GET /session_timeout`.
expected_endpoints = [
  Endpoint.new("/real", "GET"),
  Endpoint.new("/admin/panel", "GET"),
]

tester = FunctionalTester.new("fixtures/perl/mojolicious_scoping/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("perl_mojolicious"),
})
tester.perform_tests

it "does not read the neighbouring Dancer2 app as Mojolicious routes" do
  paths = tester.endpoints.flat_map { |endpoint| endpoint.details.code_paths.map(&.path) }
  paths.any?(&.includes?("dancer2app")).should be_false

  urls = tester.endpoints.map(&.url)
  %w[/page /limit /q /email /status /dashboard /settings].each do |stolen|
    urls.should_not contain(stolen)
  end
end

it "does not report data accessors spelled ->get('literal') as routes" do
  urls = tester.endpoints.map(&.url)
  urls.should_not contain("/session_timeout")
  urls.should_not contain("/current_user")
  urls.should_not contain("/secret_name")
end
