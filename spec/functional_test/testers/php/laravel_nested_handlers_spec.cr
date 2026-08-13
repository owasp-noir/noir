require "../../func_spec.cr"

# A `Route::…` call inside another route's handler body is not a route
# registration: the closure runs when a request hits the outer route, not at
# boot, so nothing it registers is attack surface.
#
# The scan that owned the outer route already skipped its body, but each of the
# six scans started at offset 0 and knew nothing about the others' skips — so
# whether a nested call leaked out depended on which scan shape happened to
# find it first. `Route::get` inside `Route::get` was suppressed; the same call
# inside a `Route::any` or behind a fluent `->post(...)` was emitted at top
# level, and without the enclosing prefix.
#
# The four `/phantom-*` paths in the fixture are the ones that used to leak.
# They are asserted absent by the endpoint-count check plus the explicit
# examples below.
expected_endpoints = [
  Endpoint.new("/same-scan", "GET"),
  Endpoint.new("/any-outer", "GET"),
  Endpoint.new("/any-outer", "POST"),
  Endpoint.new("/any-outer", "PUT"),
  Endpoint.new("/any-outer", "PATCH"),
  Endpoint.new("/any-outer", "DELETE"),
  Endpoint.new("/any-outer", "OPTIONS"),
  Endpoint.new("/any-outer", "HEAD"),
  Endpoint.new("/chain/chained-outer", "POST"),
  # The canonical `Route::group` nesting still resolves, prefix and all.
  Endpoint.new("/admin/users", "GET"),
  Endpoint.new("/admin/users", "POST"),
]

FunctionalTester.new("fixtures/php/laravel_nested_handlers/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Laravel routes nested in a handler body" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "registers none of them, whichever scan would have found them" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/php/laravel_nested_handlers/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    urls = app.endpoints.map(&.url)
    urls.should_not contain("/phantom-same-scan")
    urls.should_not contain("/phantom-in-any")
    urls.should_not contain("/phantom-in-chain")
    urls.should_not contain("/phantom-static")
    # …and not under the enclosing prefix either, which is how they surfaced.
    urls.should_not contain("/chain/phantom-in-chain")
  end
end
