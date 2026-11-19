require "../../func_spec.cr"

# Request input mapped onto action arguments (`#[MapQueryParameter]`,
# `#[MapQueryString]`, `#[MapRequestPayload]`, `#[MapUploadedFile]`) and the
# decoded body read through `$request->getPayload()`.
expected_endpoints = [
  Endpoint.new("/control", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/search", "GET", [Param.new("term", "", "query"), Param.new("per-page", "", "query")]),
  Endpoint.new("/filter", "GET", [Param.new("name", "", "query"), Param.new("email", "", "query"), Param.new("age", "", "query")]),
  Endpoint.new("/users", "POST", [Param.new("name", "", "json"), Param.new("email", "", "json"), Param.new("age", "", "json")]),
  Endpoint.new("/avatar", "POST", [Param.new("picture", "", "file")]),
  Endpoint.new("/payload", "POST", [Param.new("title", "", "json")]),
  Endpoint.new("/me", "POST"),
]

tester = FunctionalTester.new("fixtures/php/symfony_argument_mapping/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Symfony argument mapping", tags: "functional" do
  it "reads no input from other argument attributes or a DTO outside the tree" do
    tester.app.endpoints.find! { |ep| ep.url == "/me" }.params.should be_empty
  end
end
