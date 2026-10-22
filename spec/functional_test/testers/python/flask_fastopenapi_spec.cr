require "../../func_spec.cr"

# fastopenapi's `FlaskRouter` routes are mounted on the Flask app under the
# prefix of `include_router(router, prefix=...)`, which lives in another file
# and may be called on an expression (`cast(..., router).include_router`).
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/console/api/setup", "GET"),
  Endpoint.new("/console/api/setup", "POST"),
]

tester = FunctionalTester.new("fixtures/python/flask_fastopenapi/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "names the decorated function as the fastopenapi route handler", tags: "functional" do
  setup = tester.app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/console/api/setup" }
  setup.handler.should eq(Handler.new("setup_system", "./spec/functional_test/fixtures/python/flask_fastopenapi/controllers/setup.py", 13))
end
