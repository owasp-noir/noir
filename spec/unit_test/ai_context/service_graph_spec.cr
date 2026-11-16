require "../../spec_helper"
require "../../../src/ai_context/service_graph"
require "../../../src/cli/inspect"
require "../../../src/output_builder/mermaid"
require "../../../src/models/noir"
require "file_utils"

private def service_endpoint(project : String, url : String, method = "GET", snippet : String? = nil) : Endpoint
  endpoint = Endpoint.new(url, method)
  details = endpoint.details
  details.project = project
  endpoint.details = details
  if snippet
    context = AIContext.new
    context.push_sink(AIContextEntry.new("outbound_http", "fetch", path: "app.js", line: 10, snippet: snippet))
    endpoint.ai_context = context
  end
  endpoint
end

describe NoirAIContext::ServiceGraph do
  it "links cross-project requests on both sides with path and call-site evidence" do
    caller = service_endpoint("web", "/checkout", snippet: "fetch('/orders/42')")
    callee = service_endpoint("orders", "/orders/{id}")
    endpoints = [caller, callee]
    NoirAIContext::ServiceGraph.apply(endpoints)
    call = caller.calls.first
    call.method.should eq("GET")
    call.url.should eq("/orders/42")
    call.matches.map(&.matched_by).should eq(["path_pattern"])
    call.matches.first.endpoint.project.should eq("orders")
    callee.called_by.first.endpoint.project.should eq("web")
    callee.called_by.first.path.should eq("app.js")
    callee.called_by.first.line.should eq(10)
    caller.ai_context.not_nil!.sinks.size.should eq(1)
    NoirAIContext::ServiceGraph.apply(endpoints)
    callee.called_by.size.should eq(1)
    caller.calls.size.should eq(1)
  end

  it "preserves ambiguous path-only matches and excludes the caller project, client stubs and non-HTTP surfaces" do
    caller = service_endpoint("web", "/start", snippet: "fetch('/orders/42')")
    local = service_endpoint("web", "/orders/:id")
    stub = service_endpoint("client", "/orders/:id")
    stub.internal = true
    mobile = service_endpoint("mobile", "/orders/:id")
    mobile.protocol = "mobile-scheme"
    endpoints = [caller, local, stub, mobile, service_endpoint("one", "/orders/:id"), service_endpoint("two", "/orders/{id}")]
    NoirAIContext::ServiceGraph.apply(endpoints)
    caller.calls.first.matches.map(&.endpoint.project).sort!.should eq(["one", "two"])
  end

  it "uses methods and explicit authorities, retaining unmatched and unresolved calls" do
    caller = service_endpoint("web", "/start", snippet: "axios.post('https://orders.local/orders')")
    good = service_endpoint("orders", "https://orders.local/orders", "POST")
    endpoints = [caller, good, service_endpoint("wrong-host", "https://other.local/orders", "POST"), service_endpoint("wrong-method", "/orders", "GET")]
    NoirAIContext::ServiceGraph.apply(endpoints)
    caller.calls.first.matches.map(&.endpoint.project).should eq(["orders"])
    caller.calls.first.matches.first.matched_by.should eq("url_exact")
    unknown = service_endpoint("web", "/unknown", snippet: "fetch(target)")
    missing = service_endpoint("web", "/missing", snippet: "fetch('/not-served')")
    no_project = service_endpoint("", "/no-project", snippet: "fetch('/orders')")
    NoirAIContext::ServiceGraph.apply([unknown, missing, no_project, good])
    unknown.calls.first.url.should be_nil
    unknown.calls.first.matches.should be_empty
    missing.calls.first.url.should eq("/not-served")
    missing.calls.first.matches.should be_empty
    no_project.calls.first.matches.should be_empty
  end

  it "matches concatenated and interpolated path segments without guessing partial segments or catch-all routes" do
    ["fetch('/orders/' + id)", "fetch(`/orders/${id}`)", "requests.get(f'/orders/{id}')"].each do |snippet|
      caller = service_endpoint("web", "/start", snippet: snippet)
      NoirAIContext::ServiceGraph.apply([caller, service_endpoint("orders", "/orders/<int:pk>"), service_endpoint("fallback", "/*")])
      caller.calls.first.matches.map(&.endpoint.project).should eq(["orders"])
      caller.calls.first.matches.first.matched_by.should eq("path_template")
    end
    ["fetch('/orders/' + buildId())", "fetch('/orders/pre-' + id)", "fetch(prefix + '/orders')", "fetch('/orders'.format(id))"].each do |snippet|
      sink = AIContextEntry.new("outbound_http", "fetch", snippet: snippet)
      NoirAIContext::OutboundRequest.targets(sink).compact_map(&.url).should be_empty
    end
  end

  it "does not default a dynamic fetch method to GET or take another line's URL" do
    sink = AIContextEntry.new("outbound_http", "fetch", snippet: "fetch('/orders', options)")
    NoirAIContext::OutboundRequest.targets(sink).first.method.should be_nil
    sink = AIContextEntry.new("outbound_http", "fetch", source: "callee", line: 10,
      snippet: "9: fetch('/wrong') | 10: fetch(target) | 11: fetch('/also-wrong')")
    NoirAIContext::OutboundRequest.targets(sink).compact_map(&.url).should be_empty
  end

  it "attributes same-line callees and treats Fetch options conservatively" do
    source = "10: fetch('/a'); axios.post('/b') | 11: fetch('/wrong')"
    sink = AIContextEntry.new("outbound_http", "axios", source: "callee", line: 10, snippet: source)
    targets = NoirAIContext::OutboundRequest.targets(sink)
    targets.map(&.url).should eq(["/b"])
    targets.first.method.should eq("POST")
    ["{headers: {method: 'POST'}}", "{method:'GET', ...options}", "{method:'GET', method:'POST'}"].each do |options|
      sink = AIContextEntry.new("outbound_http", "fetch", snippet: "fetch('/orders', #{options})")
      NoirAIContext::OutboundRequest.targets(sink).first.method.should be_nil
    end
    sink = AIContextEntry.new("outbound_http", "fetch", snippet: "fetch('/orders', {method: 'POST'})")
    NoirAIContext::OutboundRequest.targets(sink).first.method.should eq("POST")
  end

  it "keeps noninterpolated braces literal and accepts anchored catch-all routes" do
    caller = service_endpoint("web", "/start", snippet: "fetch('/orders/{id}')")
    NoirAIContext::ServiceGraph.apply([caller, service_endpoint("orders", "/orders/<int:pk>")])
    caller.calls.first.matches.should be_empty
    caller = service_endpoint("web", "/start", snippet: "fetch('https://ORDERS.local:443/orders/status')")
    endpoints = [caller, service_endpoint("orders", "https://orders.local/orders/*"), service_endpoint("fallback", "/*")]
    NoirAIContext::ServiceGraph.apply(endpoints)
    caller.calls.first.matches.map(&.endpoint.project).should eq(["orders"])
    caller.calls.first.matches.first.matched_by.should eq("url_wildcard")
  end

  it "preserves route variants with different request conditions through tracing and reports" do
    caller = service_endpoint("web", "/start", snippet: "fetch('/orders')")
    one = service_endpoint("orders", "/orders", snippet: "fetch('/one')")
    two = service_endpoint("orders", "/orders", snippet: "fetch('/two')")
    one.route_conditions = [Param.new("mode", "one", "query")]
    two.route_conditions = [Param.new("mode", "two", "query")]
    endpoints = [caller, one, two, service_endpoint("one", "/one"), service_endpoint("two", "/two")]
    NoirAIContext::ServiceGraph.apply(endpoints)
    caller.calls.first.matches.size.should eq(2)
    endpoints = Array(Endpoint).from_json(endpoints.to_json)
    # References include the condition identity even though route_conditions
    # itself is internal. Recovering a report must retain both variants.
    rows = Noir::CLI::Inspect.service_trace_rows(Noir::CLI::Inspect.trace(endpoints, "GET", "/start"), endpoints, true)
    rows.map(&.url).sort!.should eq(["/one", "/orders", "/orders", "/start", "/two"])
    roots = Noir::CLI::Inspect.trace([one, two], "GET", "/orders")
    Noir::CLI::Inspect.service_trace_rows(roots, [one, two], true).size.should eq(2)
  end

  it "does not link call-shaped strings or comments beside a real sink" do
    ["const note = \"fetch('/admin')\"; fetch(target);", "fetch(target); // fetch('/admin')",
     "fetch(target); # fetch('/admin')", "/* fetch('/admin') */ fetch(target);"].each do |code|
      sink = AIContextEntry.new("outbound_http", "fetch", source: "callee", line: 10, snippet: "10: #{code}")
      NoirAIContext::OutboundRequest.targets(sink).compact_map(&.url).should be_empty
    end
  end

  it "roundtrips finite edges through JSON and YAML and follows cycles once" do
    one = service_endpoint("one", "/one", snippet: "fetch('/two')")
    two = service_endpoint("two", "/two", snippet: "fetch('/one')")
    endpoints = [one, two]
    NoirAIContext::ServiceGraph.apply(endpoints)
    endpoints = Array(Endpoint).from_json(endpoints.to_json)
    endpoints = Array(Endpoint).from_yaml(endpoints.to_yaml)
    rows = Noir::CLI::Inspect.service_trace_rows(Noir::CLI::Inspect.trace(endpoints, "GET", "/one"), endpoints, true)
    rows.map(&.url).should eq(["/one", "/two"])
    rows.last.via.first.kind.should eq("service_call")
    rows.last.matched_by.should eq("path_exact")
    Endpoint.new("/plain", "GET").to_json.should_not contain("called_by")
    Endpoint.new("/plain", "GET").to_json.should_not contain("\"calls\"")
  end

  it "renders a service graph including unresolved calls with safe labels" do
    caller = service_endpoint("web\"] --> injected", "/start", snippet: "fetch('/orders/42'); fetch(target)")
    callee = service_endpoint("orders", "/orders/{id}")
    unknown = service_endpoint("web", "/unknown", snippet: "fetch(target)")
    endpoints = [caller, callee, unknown]
    NoirAIContext::ServiceGraph.apply(endpoints)
    builder = OutputBuilderMermaid.new(create_test_options)
    builder.io = IO::Memory.new
    builder.print(endpoints)
    output = builder.io.to_s
    output.should contain("flowchart LR")
    caller.calls.any? { |call| call.url.nil? }.should be_true
    output.should contain("path_pattern")
    output.should contain("unresolved: fetch")
    output.should_not contain("web\"] --> injected")
  end

  it "links a real monorepo scan after project assignment and context building" do
    root = File.tempname("noir-service-graph")
    begin
      {"web"    => "app.get('/start', (req, res) => { fetch('/orders/42'); res.send('ok'); });",
       "orders" => "app.get('/orders/:id', (req, res) => { res.json({id: req.params.id}); });"}.each do |project, route|
        dir = File.join(root, project)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "package.json"), %({"dependencies":{"express":"5.0.0"}}))
        File.write(File.join(dir, "app.js"), "const express = require('express');\nconst app = express();\n#{route}\n")
      end
      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(root)])
      options["ai_context"] = YAML::Any.new(true)
      runner = NoirRunner.new(options)
      runner.detect
      runner.analyze
      caller = runner.endpoints.find! { |endpoint| endpoint.url == "/start" }
      caller.details.project.should eq("web")
      caller.calls.flat_map(&.matches).map(&.endpoint.project).should contain("orders")
      callee = runner.endpoints.find! { |endpoint| endpoint.url == "/orders/:id" }
      callee.called_by.map(&.endpoint.project).should contain("web")
    ensure
      CodeLocator.instance.reset_files
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end
