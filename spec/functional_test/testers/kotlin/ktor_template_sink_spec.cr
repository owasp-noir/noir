require "../../func_spec.cr"

# Ktor `call.respond(x)` serializes data; it is a template render only for a
# template plugin's content, named at the call or imported by the file.
describe "Ktor call.respond template sinks", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "keeps the template sink only for template content" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/ktor_template_sink/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    renders = ->(url : String) do
      endpoint = app.endpoints.find { |item| item.method == "GET" && item.url == url }
      fail("missing GET #{url}") unless endpoint
      (endpoint.ai_context.try(&.sinks) || [] of AIContextEntry).any? { |sink| sink.kind == "template_render" }
    end

    renders.call("/healthz").should be_false
    renders.call("/votes").should be_false
    renders.call("/qualified").should be_true
    renders.call("/index").should be_true
    renders.call("/built").should be_true
  end
end
