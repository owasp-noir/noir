require "../../func_spec.cr"

# Resource routes behind a fluent chain (`Route::middleware('auth')->resource(...)`,
# `Route::prefix('admin')->...->apiResource(...)`, a chained `singleton`), and
# the `Route::inertia()` / `Route::livewire()` page macros. A chained resource
# inside a group is reported once, under the group's prefix; a class in the
# chain's middleware is not taken for the controller.
expected_endpoints = [
  Endpoint.new("/control", "GET"),
  Endpoint.new("/photos", "GET"),
  Endpoint.new("/photos", "POST"),
  Endpoint.new("/admin/users", "GET"),
  Endpoint.new("/admin/users/{user}", "DELETE", [Param.new("user", "", "path")]),
  Endpoint.new("/profile", "GET"),
  Endpoint.new("/profile/edit", "GET"),
  Endpoint.new("/profile", "PUT"),
  Endpoint.new("/profile", "PATCH"),
  Endpoint.new("/albums", "GET"),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/posts/create", "GET"),
  Endpoint.new("/settings", "GET"),
  Endpoint.new("/team/members", "GET"),
]

tester = FunctionalTester.new("fixtures/php/laravel_resource_chains/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {"ai_context" => YAML::Any.new(true)})
tester.perform_tests

describe "Laravel chained resource routes", tags: "functional" do
  it "applies the chain's middleware and resolves the resource's own controller" do
    find = ->(method : String, url : String) { tester.app.endpoints.find! { |ep| ep.method == method && ep.url == url } }

    find.call("POST", "/photos").tags.map(&.name).should contain("auth")
    find.call("DELETE", "/admin/users/{user}").tags.map(&.name).should contain("auth")
    find.call("PATCH", "/profile").tags.map(&.name).should contain("auth")
    find.call("GET", "/settings").tags.map(&.name).should contain("auth")
    find.call("GET", "/about").tags.map(&.name).should_not contain("auth")
    find.call("GET", "/albums").handler.try(&.name).should eq("PhotoController@index")
  end
end
