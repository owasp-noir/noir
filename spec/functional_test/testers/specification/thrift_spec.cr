require "../../func_spec.cr"

def thrift_endpoint(url : String, params : Array(Param)) : Endpoint
  endpoint = Endpoint.new(url, "POST", params)
  endpoint.protocol = "thrift"
  endpoint
end

expected_endpoints = [
  # The issue's own example, plus `extends shared.SharedService`.
  thrift_endpoint("/UserService/getUser", [Param.new("id", "", "json")]),
  thrift_endpoint("/UserService/deleteUser", [Param.new("id", "", "json")]),
  # Multiline args with requiredness, a nested container and a default.
  thrift_endpoint("/UserService/searchUsers", [
    Param.new("query", "", "json"),
    Param.new("filters", "", "json"),
    Param.new("limit", "", "json"),
  ]),
  # oneway, `;`-separated args.
  thrift_endpoint("/UserService/logEvent", [
    Param.new("event", "", "json"),
    Param.new("timestamp", "", "json"),
  ]),
  # Args with no separator between them and a trailing annotation.
  thrift_endpoint("/UserService/updateUser", [
    Param.new("id", "", "json"),
    Param.new("user", "", "json"),
  ]),
  # Inherited through shared.SharedService -> base.BaseService across includes.
  thrift_endpoint("/UserService/getStruct", [Param.new("key", "", "json")]),
  thrift_endpoint("/UserService/ping", [] of Param),
  # `include "monitor.thrift"` resolved through a search path (common/).
  thrift_endpoint("/HealthService/status", [Param.new("verbose", "", "json")]),
  # The included services are service files in their own right.
  thrift_endpoint("/SharedService/getStruct", [Param.new("key", "", "json")]),
  thrift_endpoint("/SharedService/ping", [] of Param),
  thrift_endpoint("/BaseService/ping", [] of Param),
  thrift_endpoint("/Monitor/status", [Param.new("verbose", "", "json")]),
]

FunctionalTester.new("fixtures/specification/thrift/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Thrift endpoint metadata", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "tags oneway/inherited functions, records field declarations and skips HTTP heuristics" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/specification/thrift/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints

    log_event = endpoints.find! { |endpoint| endpoint.url == "/UserService/logEvent" }
    log_event.tags.map(&.name).should contain("oneway")
    log_event.details.code_paths.first.line.should eq(37)

    get_user = endpoints.find! { |endpoint| endpoint.url == "/UserService/getUser" }
    get_user.tags.map(&.name).should_not contain("oneway")
    get_user.tags.map(&.name).should_not contain("thrift-inherited")

    search = endpoints.find! { |endpoint| endpoint.url == "/UserService/searchUsers" }
    declarations = search.params.to_h { |param| {param.name, param.tags.find!(&.name.==("thrift-field")).description} }
    declarations.should eq({
      "query"   => "1: required string",
      "filters" => "2: optional map<string, list<i32>>",
      "limit"   => "3: i32",
    })

    ping = endpoints.find! { |endpoint| endpoint.url == "/UserService/ping" }
    ping.tags.find!(&.name.==("thrift-inherited")).description.should eq("Inherited from base.BaseService")
    ping.details.code_paths.first.path.should end_with("common/base.thrift")

    endpoints.each do |endpoint|
      endpoint.protocol.should eq("thrift")
      context = endpoint.ai_context.should_not be_nil
      context.signals.map(&.kind).should_not contain("state_change")
      context.signals.map(&.kind).should_not contain("guard_absence")
    end
  end
end

# Two projects in one scan, each with its own `common/shared.thrift` on the
# include path: `shared.Base` resolves to the copy beside the including file.
FunctionalTester.new("fixtures/specification/thrift_multi_project/", {
  :techs     => 1,
  :endpoints => 4,
}, [
  thrift_endpoint("/SvcA/ping_a", [] of Param),
  thrift_endpoint("/SvcB/ping_b", [] of Param),
]).perform_tests
