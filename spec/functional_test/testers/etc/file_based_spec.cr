require "../../func_spec.cr"
require "json" # Ensure json is at top if structs use it
require "process" # Ensure Process is available at top

# Helper structs for parsing, matching the structure in src/models/endpoint.cr
# Moved to top-level to avoid "can't declare class dynamically" error.
# Note: The Endpoint and Param structs used by extected_endpoints are from func_spec.cr via noir models,
# not these Test* structs. These Test* structs are for the separate GraphQL CLI test.
struct TestPathInfo
  include JSON::Serializable
  property path : String
  property line : Int32 | Nil
end

struct TestDetails
  include JSON::Serializable
  property code_paths : Array(TestPathInfo) = [] of TestPathInfo
end

struct TestParam
  include JSON::Serializable
  property name : String
  property value : String
  property param_type : String
end

struct TestEndpoint
  include JSON::Serializable
  property url : String
  property method : String
  property params : Array(TestParam) = [] of TestParam
  property details : TestDetails
end

# Corrected spelling from extected_endpoints to expected_endpoints
expected_endpoints = [
  Endpoint.new("https://www.hahwul.com/", "GET"),
  Endpoint.new("https://www.hahwul.com/about", "GET"),
  Endpoint.new("https://www.hahwul.com/cullinan", "GET"),
  Endpoint.new("https://www.hahwul.com/phoenix", "GET"),
  Endpoint.new("https://www.hahwul.com/tag/security/", "GET"),
  Endpoint.new("https://www.hahwul.com/tag/crystal/", "GET"),
  Endpoint.new("https://www.hahwul.com/tag/zap/", "GET"),
  Endpoint.new("https://www.hahwul.com/form_http", "POST", [Param.new("X-API-Key", "1234", "header"), Param.new("a", "1234", "form")]),
  Endpoint.new("https://www.hahwul.com/json_http", "POST", [Param.new("name", "test", "json"), Param.new("data", "abcd", "json")]),
  Endpoint.new("https://www.hahwul.com/query_http", "GET", [Param.new("q", "1234", "query"), Param.new("Authorization", "abcd", "header")]),
  Endpoint.new("https://www.hahwul.com/multiple_http1", "GET"),
  Endpoint.new("https://www.hahwul.com/multiple_http2", "GET"),
  # Add the new GraphQL endpoint expected from sample.graphql
  # The FunctionalTester seems to combine the URL option with the path.
  # The actual endpoint produced by GraphqlAnalyzer is POST /graphql.
  # The FunctionalTester error was "POST::https://www.hahwul.com/graphql not found"
  # This implies the URL it's looking for in the expected_endpoints list is the fully qualified one.
  # Simplified parameter expectation for POST /graphql for FunctionalTester.
  # FunctionalTester's current comparison logic may not fully align with
  # GraphQL's single-URL, multi-operation-with-distinct-params model.
  # This expects only the 'GetUserData' operation's params. Other operations' params
  # on this endpoint might be flagged by FunctionalTester if not explicitly listed here.
  # Detailed param validation is in the GraphQL-specific test.
  Endpoint.new("https://www.hahwul.com/graphql", "POST", [
    Param.new("graphql_operation_query_GetUserData", "{\"query\":\"GetUserData\"}", "json")
  ]),
]

tester = FunctionalTester.new("fixtures/etc/file_based/", {
  :techs     => 0,
  # Adjusted count: original 12 + 1 new unique GraphQL endpoint (POST /graphql)
  :endpoints => expected_endpoints.size, # This will now be 13 if original was 12
}, expected_endpoints)

tester.app.options["url"] = YAML::Any.new("https://www.hahwul.com")

# Wrap the call to tester.perform_tests (formerly tester.test_all) in a describe block
describe "Functional test for file_based fixtures (Original Tests)" do
  tester.perform_tests
end

# Add new test case for GraphQL
# 'require "json"' and 'require "process"' moved to top

describe "GraphQL File Analysis" do
  # Structs are now defined at the top level.

  it "correctly extracts endpoints from .graphql files" do
    graphql_fixture_path = "./spec/functional_test/fixtures/etc/file_based/sample.graphql"
    # Adjust binary path if needed, assuming it's relative to repo root
    command = "./bin/noir #{graphql_fixture_path} -o json --no-banner --no-log"

    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    process_status = Process.run(command, shell: true, output: stdout_io, error: stderr_io)
    stdout_string = stdout_io.gets_to_end
    stderr_string = stderr_io.gets_to_end

    # Debug output if needed
    # puts "STDOUT: #{stdout_string}"
    puts "STDERR for GraphQL test: #{stderr_string}" if !process_status.success?

    process_status.success?.should be_true # Check if the command executed successfully

    # Parse the JSON output
    # The output is an array of Endpoint-like objects
    # The structure is defined in src/models/output_builder.cr -> build_json_output -> results["endpoints"]
    # It seems to be directly an array of Endpoints.
    parsed_output = JSON.parse(stdout_string)
    # Assuming the root of the JSON output is the array of endpoints.
    # If it's nested under a key like {"endpoints": [...]}, adjust here.
    # Based on typical noir output, it might be directly an array if only endpoints are requested.
    # Let's assume it's Array(TestEndpoint) for now.

    # If JSON.parse gives Array(JSON::Any), we need to map it to Array(TestEndpoint)
    # For simplicity, let's assume direct parsing or handle it if it fails.
    # endpoints = Array(TestEndpoint).from_json(stdout_string) would be ideal.

    # Given the complexity, let's parse into Array(JSON::Any) and then manually check fields
    # or map to our TestEndpoint struct.
    # For now, let's try parsing directly to the array of structs.
    endpoints = Array(TestEndpoint).from_json(stdout_string)


    endpoints.size.should eq(3) # Expect 3 endpoints

    # Expected operations and their details
    expected_ops = [
      { name: "GetUserData", type: "query", line: 3 },
      { name: "UpdateUserProfile", type: "mutation", line: 11 },
      { name: "ListItems", type: "query", line: 19 },
    ]

    expected_ops.each do |op_info|
      operation_name = op_info[:name]
      operation_type = op_info[:type]
      expected_line = op_info[:line]

      # Find the endpoint corresponding to this operation
      # We'll check the param's value for this
      endpoint = endpoints.find do |ep|
        next false if ep.params.empty?
        param_json_value = ep.params[0].value
        parsed_param_value = JSON.parse(param_json_value).as_h
        parsed_param_value[operation_type]? == operation_name
      end

      # Corrected: be_nil matcher does not take a message argument directly.
      # The 'it' block description or surrounding logic should provide context for failures.
      endpoint.should_not be_nil

      unless endpoint # Guard further assertions if endpoint is nil
        # This line will not be reached if the above assertion fails,
        # but it's good practice if we were not using should_not.
        # For now, the should_not be_nil is idiomatic.
        fail "Critical: Endpoint for #{operation_type} #{operation_name} was nil, stopping further checks for this op."
        # Or simply return/next from the loop if appropriate
      end

      ep = endpoint.not_nil! # Shadow for type safety, now safe due to above check or assertion

      ep.url.should eq("/graphql")
      ep.method.should eq("POST")

      ep.params.size.should eq(1)
      param = ep.params[0]
      param.param_type.should eq("json")
      # Expected param name e.g. graphql_operation_query_GetUserData
      param.name.should eq("graphql_operation_#{operation_type}_#{operation_name}")

      # Verify param value (JSON string)
      parsed_param_value = JSON.parse(param.value).as_h
      parsed_param_value.size.should eq(1)
      parsed_param_value[operation_type]?.should eq(operation_name)

      # Verify code path and line number
      ep.details.code_paths.size.should eq(1)
      path_info = ep.details.code_paths[0]
      path_info.path.ends_with?("spec/functional_test/fixtures/etc/file_based/sample.graphql").should be_true
      path_info.line.should eq(expected_line)
    end
  end
end
