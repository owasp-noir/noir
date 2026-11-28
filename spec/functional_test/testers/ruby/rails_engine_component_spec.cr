require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/billing/locations", "GET"),
  Endpoint.new("/billing/locations/new", "GET"),
  Endpoint.new("/billing/locations", "POST", [Param.new("name", "", "form")]),
  Endpoint.new("/billing/locations/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/billing/locations/:id/edit", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/billing/locations/:id", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/billing/locations/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/billing/locations/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/billing/status", "GET"),
  Endpoint.new("/billing/ping", "GET"),
  Endpoint.new("/billing/old", "GET"),
  Endpoint.new("/billing/export", "GET"),
  Endpoint.new("/billing", "GET"),
  Endpoint.new("/reports", "GET"),
  Endpoint.new("/reports/summaries", "GET"),
  Endpoint.new("/ledger", "GET"),
  Endpoint.new("/ledger/entries", "GET"),
  Endpoint.new("/ledger/entries/:id", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/ruby/rails_engine_component/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Rails engine controllers under a component directory", tags: "functional" do
  it "applies guards inherited from the engine's own ApplicationController" do
    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/ruby/rails_engine_component/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    guards = app.endpoints.to_h do |ep|
      {"#{ep.method} #{ep.url}", ep.tags.select(&.name.in?("auth", "authz")).map(&.name)}
    end
    guards["GET /billing/locations"].should eq(["auth"])
    guards["DELETE /billing/locations/:id"].should eq(["auth"])
    guards["GET /billing/status"].should be_empty
    guards["GET /ledger/entries"].should eq(["auth"])
  ensure
    CodeLocator.instance.clear_all
  end
end
