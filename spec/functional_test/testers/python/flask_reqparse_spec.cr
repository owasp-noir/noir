require "../../func_spec.cr"

# flask-restful `reqparse`: the `add_argument` calls on the parser a handler
# reads with `parse_args()`, whether the parser is module-level, built in the
# handler, `self.reqparse` from `__init__`, or imported and `.copy()`-extended.
# An argument without `location=` is a query param on GET and JSON otherwise.
expected_endpoints = [
  Endpoint.new("/todos", "GET", [
    Param.new("task", "", "query"),
    Param.new("rate", "", "query"),
    Param.new("page", "", "query"),
    Param.new("X-Api-Key", "", "header"),
    Param.new("session_id", "", "cookie"),
  ]),
  Endpoint.new("/todos", "POST", [
    Param.new("task", "", "json"),
    Param.new("rate", "", "json"),
    Param.new("page", "", "query"),
    Param.new("X-Api-Key", "", "header"),
    Param.new("session_id", "", "cookie"),
    Param.new("picture", "", "form"),
    Param.new("pub_name", "", "form"),
  ]),
  Endpoint.new("/todos/<todo_id>", "PUT", [
    Param.new("todo_id", "", "path"),
    Param.new("done", "", "json"),
  ]),
  Endpoint.new("/todos/<todo_id>", "PATCH", [
    Param.new("todo_id", "", "path"),
    Param.new("note", "", "form"),
    Param.new("title", "", "json"),
  ]),
  Endpoint.new("/search", "GET", [
    Param.new("term", "", "query"),
    Param.new("limit", "", "query"),
    Param.new("cursor", "", "query"),
  ]),
  Endpoint.new("/cli", "GET"),
]

FunctionalTester.new("fixtures/python/flask_reqparse/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Flask reqparse arguments", tags: "functional" do
  it "reads only the parser parse_args is called on" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/flask_reqparse/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.endpoints.find! { |ep| ep.url == "/cli" }.params.should be_empty
    get = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/todos" }
    get.params.map(&.param_type).should_not contain("json")
    put = app.endpoints.find! { |ep| ep.method == "PUT" }
    put.params.map(&.name).should_not contain("task")
  end
end
