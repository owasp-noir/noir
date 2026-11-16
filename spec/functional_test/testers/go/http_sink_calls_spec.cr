require "../../func_spec.cr"

# Go's database/sql spells a query `QueryRow` / `QueryContext` /
# `ExecContext`, and GORM runs a raw statement through `Raw`: each is an
# `sql` sink. `http.Dir` names a directory for `http.FileServer`; it sends
# no request, so a static file server is not an `outbound_http` sink.
describe "--ai-context sinks of Go database and file-server calls", tags: "functional" do
  sinks = {} of String => Array(String)

  before_all do
    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/go/http_sink_calls/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    sinks = app.endpoints.to_h do |ep|
      {"#{ep.method} #{ep.url}", ep.ai_context.try(&.sinks.map(&.kind).uniq!) || [] of String}
    end
  end

  it "reads QueryRow, QueryContext, ExecContext and GORM's Raw as sql sinks" do
    ["GET /orders/{id}", "GET /orders", "DELETE /orders/{id}", "GET /reports/{name}"].each do |route|
      sinks[route].should contain("sql")
    end
  end

  it "leaves a handler with no query without one" do
    sinks["GET /health"].should_not contain("sql")
  end

  it "does not read http.Dir as an outbound request" do
    sinks["GET /static/"].should eq(["file_io"])
  end
end
