require "../../spec_helper"
require "../../../src/output_builder/common"
require "../../../src/output_builder/curl"
require "../../../src/output_builder/diff"
require "../../../src/output_builder/httpie"
require "../../../src/output_builder/markdown_table"
require "../../../src/output_builder/oas3"
require "../../../src/output_builder/postman"

private def scoped_health_endpoint(project : String, param : String) : Endpoint
  details = Details.new(PathInfo.new("#{project}/app.py", 42))
  details.origins = [Origin.new("python_fastapi", "code", project: project)]
  Endpoint.new("https://example.test/health", "GET", [Param.new(param, "", "query")], details)
end

private def verify_project_labels(builder, endpoints : Array(Endpoint)) : String
  builder.io = IO::Memory.new
  builder.print(endpoints)
  output = builder.io.to_s
  output.should contain("orders")
  output.should contain("users")
  output
end

describe "output builders with endpoint origins" do
  it "prints project labels for coincident routes and source locations in Markdown" do
    options = create_test_options
    options["include_path"] = YAML::Any.new(true)
    endpoints = [scoped_health_endpoint("orders", "detail"), scoped_health_endpoint("users", "detail")]

    verify_project_labels(OutputBuilderCommon.new(options), endpoints)
    verify_project_labels(OutputBuilderCurl.new(options), endpoints)
    verify_project_labels(OutputBuilderHttpie.new(options), endpoints)
    verify_project_labels(OutputBuilderPostman.new(options), endpoints)
    markdown = verify_project_labels(OutputBuilderMarkdownTable.new(options), endpoints)
    markdown.should contain("orders/app.py:42")
    markdown.should contain("users/app.py:42")
  end

  it "keeps distinct origins in a single OpenAPI operation" do
    options = create_test_options
    builder = OutputBuilderOas3.new(options)
    builder.io = IO::Memory.new
    builder.print([scoped_health_endpoint("orders", "detail"), scoped_health_endpoint("users", "status")])
    operation = JSON.parse(builder.io.to_s)["paths"]["/health"]["get"]

    operation["x-noir-projects"].as_a.map(&.as_s).should eq(["orders", "users"])
    operation["x-noir-origins"].as_a.map(&.["project"].as_s).should eq(["orders", "users"])
  end

  it "diffs coincident routes by project and reads their origin from JSON" do
    endpoints = [scoped_health_endpoint("orders", "detail"), scoped_health_endpoint("users", "status")]
    restored = Array(Endpoint).from_json(endpoints.to_json)
    restored.map(&.details.origins).should eq(endpoints.map(&.details.origins))
    builder = OutputBuilderDiff.new(create_test_options)
    builder.diff(restored, endpoints)[:changed].should be_empty
    builder.diff(restored.first(1), endpoints)[:removed].map(&.details.origin_projects).should eq([["users"]])
  end
end
