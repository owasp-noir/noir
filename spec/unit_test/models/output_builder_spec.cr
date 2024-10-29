require "../../../src/models/output_builder.cr"
require "../../../src/options.cr"

describe "Initialize" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  options["base"] = YAML::Any.new("noir")
  options["format"] = YAML::Any.new("json")
  options["output"] = YAML::Any.new("output.json")

  it "OutputBuilder" do
    object = OutputBuilder.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderCommon" do
    object = OutputBuilderCommon.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderCurl" do
    object = OutputBuilderCurl.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderHttpie" do
    object = OutputBuilderHttpie.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderMarkdownTable" do
    object = OutputBuilderMarkdownTable.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOas2" do
    object = OutputBuilderOas2.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOas3" do
    object = OutputBuilderOas3.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOnlyUrl" do
    object = OutputBuilderOnlyUrl.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOnlyParam" do
    object = OutputBuilderOnlyParam.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOnlyHeader" do
    object = OutputBuilderOnlyHeader.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOnlyCookie" do
    object = OutputBuilderOnlyCookie.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderJsonl" do
    object = OutputBuilderJsonl.new options
    object.output_file.should eq("output.json")
  end
end

describe OutputBuilderDiff do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  options["base"] = YAML::Any.new("noir")
  options["format"] = YAML::Any.new("json")

  it "calculates the diff correctly" do
    old_endpoints = [Endpoint.new("GET", "/old")]
    new_endpoints = [Endpoint.new("GET", "/new")]
    builder = OutputBuilderDiff.new options

    result = builder.diff(new_endpoints, old_endpoints)

    result[:added].should eq [Endpoint.new("GET", "/new")]
    result[:removed].should eq [Endpoint.new("GET", "/old")]
  end

  it "calculates the diff correctly with multiple endpoints" do
    old_endpoints = [Endpoint.new("GET", "/old"), Endpoint.new("GET", "/old2")]
    new_endpoints = [Endpoint.new("GET", "/new"), Endpoint.new("GET", "/new2")]
    builder = OutputBuilderDiff.new options

    result = builder.diff(new_endpoints, old_endpoints)

    result[:added].should eq [Endpoint.new("GET", "/new"), Endpoint.new("GET", "/new2")]
    result[:removed].should eq [Endpoint.new("GET", "/old"), Endpoint.new("GET", "/old2")]
  end

  it "calculates the diff correctly with multiple endpoints and different methods" do
    old_endpoints = [Endpoint.new("GET", "/old"), Endpoint.new("POST", "/old2")]
    new_endpoints = [Endpoint.new("GET", "/new"), Endpoint.new("POST", "/new2")]
    builder = OutputBuilderDiff.new options

    result = builder.diff(new_endpoints, old_endpoints)

    result[:added].should eq [Endpoint.new("GET", "/new"), Endpoint.new("POST", "/new2")]
    result[:removed].should eq [Endpoint.new("GET", "/old"), Endpoint.new("POST", "/old2")]
  end

  it "calculates the diff correctly with multiple endpoints and different methods and params" do
    old_endpoints = [Endpoint.new("GET", "/old", [Param.new("a", "b", "query"), Param.new("c", "d", "json")])]
    new_endpoints = [Endpoint.new("GET", "/new", [Param.new("e", "f", "query"), Param.new("g", "h", "json")])]
    builder = OutputBuilderDiff.new options

    result = builder.diff(new_endpoints, old_endpoints)

    result[:added].should eq [Endpoint.new("GET", "/new", [Param.new("e", "f", "query"), Param.new("g", "h", "json")])]
    result[:removed].should eq [Endpoint.new("GET", "/old", [Param.new("a", "b", "query"), Param.new("c", "d", "json")])]
  end
end
