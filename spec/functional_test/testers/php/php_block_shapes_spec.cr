require "../../func_spec.cr"

# Shapes that broke text parsing and that `Noir::PhpBlockParser` reads off
# the block structure instead: Laravel group chains and closures, middleware
# guest pass-throughs in `else` / `finally`, Symfony attribute groups and
# class bodies, and callees inside heredocs and multi-line strings.
private def scan_block_shapes(fixture : String, callees : Bool = false) : Array(Endpoint)
  CodeLocator.instance.clear_all
  options = ConfigInitializer.new.default_options
  options["base"] = YAML::Any.new([YAML::Any.new(fixture)])
  options["nolog"] = YAML::Any.new(true)
  options["include_callee"] = YAML::Any.new(true) if callees
  app = NoirRunner.new(options)
  app.detect
  app.analyze
  app.endpoints
end

private def auth_tags(endpoints : Array(Endpoint), method : String, url : String) : Array(String)
  endpoint = endpoints.find { |ep| ep.method == method && ep.url == url }
  fail "missing #{method} #{url} in #{endpoints.map { |ep| "#{ep.method} #{ep.url}" }}" unless endpoint
  endpoint.tags.select(&.name.==("auth")).map(&.description)
end

describe "PHP block-structure shapes", tags: "functional" do
  it "reads Laravel group chains and middleware branches off the block tree" do
    endpoints = scan_block_shapes("./spec/functional_test/fixtures/php/laravel_block_shapes/", callees: true)
    urls = endpoints.map { |ep| "#{ep.method} #{ep.url}" }

    auth_tags(endpoints, "GET", "/arrow/x").should eq(["Protected by Laravel auth middleware"])
    auth_tags(endpoints, "GET", "/semi/one").should be_empty
    auth_tags(endpoints, "GET", "/nested/two").should eq(["Protected by Laravel auth middleware"])
    auth_tags(endpoints, "GET", "/fn/four").should be_empty
    auth_tags(endpoints, "GET", "/opts/five").should be_empty
    urls.should_not contain("GET /x")
    urls.should_not contain("GET /one")
    urls.should_not contain("GET /four")
    urls.should_not contain("GET /never")

    # A guest reaching an `else` of a lone `if ($user)` or a `finally` passes.
    auth_tags(endpoints, "GET", "/mw/else-top").should be_empty
    auth_tags(endpoints, "GET", "/mw/finally").should be_empty
    # Still guards: an `else` after an `elseif`, the `else` of a guest
    # refusal, a `finally` inside a `catch`, an `else` inside a loop.
    auth_tags(endpoints, "GET", "/mw/else-after-elseif").should eq(["Protected by Laravel ElseAfterElseif middleware"])
    auth_tags(endpoints, "GET", "/mw/else-of-refusal").should eq(["Protected by Laravel ElseOfRefusal middleware"])
    auth_tags(endpoints, "GET", "/mw/finally-in-catch").should eq(["Protected by Laravel FinallyInCatch middleware"])
    auth_tags(endpoints, "GET", "/mw/else-in-loop").should eq(["Protected by Laravel ElseInLoop middleware"])

    index = endpoints.find! { |ep| ep.url == "/semi/one" }
    names = index.callees.map(&.name)
    names.should contain("RealIndex::run")
    names.should_not contain("FakeHeredoc::call")
    names.should_not contain("fake_heredoc_fn")
    names.should_not contain("FakeMulti::call")
    names.should_not contain("fake_multi_fn")
  end

  it "reads Symfony attribute groups and class bodies off the block tree" do
    endpoints = scan_block_shapes("./spec/functional_test/fixtures/php/symfony_block_shapes/")
    urls = endpoints.map { |ep| "#{ep.method} #{ep.url}" }.sort!
    urls.should eq([
      "DELETE /shape/fqcn",
      "GET /shape/after-heredoc",
      "GET /shape/doc",
      "GET /shape/me",
      "POST /shape/cond",
      "PUT /shape/grouped",
    ])
    auth_tags(endpoints, "PUT", "/shape/grouped").should eq(["Protected by Symfony #[IsGranted('ROLE_ADMIN')]"])
    auth_tags(endpoints, "GET", "/shape/me").should eq(["Protected by Symfony #[IsGranted('ROLE_USER')]"])
  end
end
