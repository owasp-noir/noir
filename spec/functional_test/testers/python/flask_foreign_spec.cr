require "../../func_spec.cr"

# A repo with BOTH a Flask app (app.py) and a FastAPI handler file
# (service.py) that uses `@app.get`/`@app.post` and never mentions flask.
# The Flask analyzer must not claim the FastAPI file — its routes belong
# to the FastAPI analyzer (python_fastapi), not python_flask.
expected_endpoints = [
  Endpoint.new("/flask-home", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/fastapi-items", "GET"),
  Endpoint.new("/fastapi-items", "POST", [Param.new("name", "", "query")]),
]

tester = FunctionalTester.new("fixtures/python/flask_foreign/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "tags FastAPI handler-file routes python_fastapi, not python_flask" do
  fastapi_route = tester.app.endpoints.find { |endpoint| endpoint.url == "/fastapi-items" && endpoint.method == "POST" }
  fastapi_route.should_not be_nil
  fastapi_route.try(&.details.technology).should eq("python_fastapi")
end
