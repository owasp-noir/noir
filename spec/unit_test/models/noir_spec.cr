require "../../spec_helper"
require "../../../src/models/noir.cr"
require "../../../src/models/endpoint.cr"
require "../../../src/optimizer/llm_optimizer.cr"
require "../../../src/utils/http_symbols.cr"

describe "Initialize" do
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])
  runner = NoirRunner.new(options)

  it "getter - options" do
    tmp_options = runner.options
    tmp_options["base"].should eq(options["base"])
  end
end

# These used to run through thin `NoirRunner` wrappers that existed only so
# the specs had something to call. They talk to the optimizer directly now —
# same code under test, one less test-only method on the runner.
private def optimizer_for(options) : LLMEndpointOptimizer
  LLMEndpointOptimizer.new(NoirLogger.new(false, false, false, true), options)
end

describe "Methods" do
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])
  options["url"] = YAML::Any.new("https://www.hahwul.com")

  it "combine_url_and_endpoints" do
    endpoints = optimizer_for(options).combine_url_and_endpoints([
      Endpoint.new("/abcd", "GET"),
      Endpoint.new("abcd", "GET"),
    ])

    endpoints[0].url.should eq("https://www.hahwul.com/abcd")
    endpoints[1].url.should eq("https://www.hahwul.com/abcd")
  end
end

describe "set-pvalue" do
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])
  options["set_pvalue_query"] = YAML::Any.new([YAML::Any.new("FUZZ")])
  options["set_pvalue_header"] = YAML::Any.new([YAML::Any.new("name=FUZZ")])
  options["set_pvalue_cookie"] = YAML::Any.new([YAML::Any.new("name:FUZZ")])
  options["set_pvalue_json"] = YAML::Any.new([YAML::Any.new("name:FUZZ=FUZZ")])
  optimizer = optimizer_for(options)

  it "applies pvalue to query parameter" do
    optimizer.apply_pvalue("query", "name", "value").should eq("FUZZ")
  end

  it "applies pvalue to header parameter with '=' delimiter" do
    optimizer.apply_pvalue("header", "name", "value").should eq("FUZZ")
  end

  it "does not apply pvalue to header parameter when name does not match" do
    optimizer.apply_pvalue("header", "name2", "value").should eq("value")
  end

  it "applies pvalue to cookie parameter with ':' delimiter" do
    optimizer.apply_pvalue("cookie", "name", "value").should eq("FUZZ")
  end

  it "does not apply pvalue to cookie parameter when name does not match" do
    optimizer.apply_pvalue("cookie", "name2", "value").should eq("value")
  end

  it "includes '=' in the pvalue for JSON parameter" do
    optimizer.apply_pvalue("json", "name", "value").should eq("FUZZ=FUZZ")
  end
end

describe "HTTP method validation" do
  options = create_test_options
  optimizer = optimizer_for(options)

  it "maintains valid HTTP methods" do
    endpoints = optimizer.optimize_endpoints([
      Endpoint.new("/valid", "GET"),
      Endpoint.new("/also-valid", "POST"),
    ])

    # Order follows the source-location sort in `optimize_endpoints`;
    # these fixtures carry no code path, so match by URL.
    endpoints.find! { |endpoint| endpoint.url == "/valid" }.method.should eq("GET")
    endpoints.find! { |endpoint| endpoint.url == "/also-valid" }.method.should eq("POST")
  end

  it "converts invalid HTTP methods to GET" do
    endpoints = optimizer.optimize_endpoints([
      Endpoint.new("/invalid-method", "INVALID"),
      Endpoint.new("/another-invalid", "test"),
    ])

    endpoints.each do |endpoint|
      if endpoint.url.includes?("invalid")
        endpoint.method.should eq("GET")
      end
    end
  end

  it "preserves all valid HTTP methods" do
    valid_methods = ALLOWED_HTTP_METHODS
    endpoints = optimizer.optimize_endpoints(
      valid_methods.map_with_index { |method, index| Endpoint.new("/endpoint#{index}", method) }
    )

    valid_methods.each_with_index do |method, index|
      endpoints.find! { |endpoint| endpoint.url == "/endpoint#{index}" }.method.should eq(method)
    end
  end
end

# `-u` is joined onto every URL before taggers and the AI-context builder
# run, but both match route text. A host or base path must not change what
# they conclude: `-u http://admin.h/auth` used to tag every route `admin`
# and make every route look like an auth route, dropping all guard_absence.
private def route_view(target : String) : Array(String)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(File.expand_path("../../functional_test/fixtures/javascript/express", __DIR__))])
  options["ai_context"] = YAML::Any.new(true)
  options["all_taggers"] = YAML::Any.new(true)
  options["url"] = YAML::Any.new(target)
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  CodeLocator.instance.reset_files
  runner.endpoints.map do |endpoint|
    endpoint.url.should start_with(target)
    {endpoint.method, endpoint.url[target.size..], endpoint.tags.map(&.name).sort!, endpoint.ai_context.to_json}.to_s
  end.sort!
end

class NoirRunner
  def __test_route_paths : Array(String)
    seen = [] of String
    with_route_paths { seen = @endpoints.map(&.url) }
    seen
  end
end

describe "NoirRunner with -u" do
  it "strips only a real -u prefix, never a longer host that starts with it" do
    options = create_test_options
    options["url"] = YAML::Any.new("http://admin.example.com")
    runner = NoirRunner.new(options)
    urls = ["http://admin.example.com/a", "http://admin.example.community/x", "http://admin.example.com"]
    runner.endpoints = urls.map { |url| Endpoint.new(url, "GET") }

    runner.__test_route_paths.should eq(["/a", "http://admin.example.community/x", "/"])
    runner.endpoints.map(&.url).should eq(urls)
  end

  it "tags and builds AI context from the route path, not the target URL" do
    plain = route_view("")
    plain.join.should contain("guard_absence")
    route_view("http://admin.h/auth").should eq(plain)
  end
end
