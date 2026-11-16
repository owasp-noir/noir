require "../../func_spec.cr"

describe "--ai-context redirect sink in Spring handlers", tags: "functional" do
  it "reads HttpServletResponse.sendRedirect and Spring redirect: view returns as redirect sinks" do
    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/java/spring_redirect_sink/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    redirects = app.endpoints.to_h do |ep|
      {"#{ep.method} #{ep.url}", ep.ai_context.try(&.sinks.select(&.kind.==("redirect")).map(&.name)) || [] of String}
    end

    redirects.should eq({
      "GET /out"    => ["response.sendRedirect"],
      "GET /go"     => ["return \"redirect:\""],
      "GET /status" => [] of String,
    })
  end
end
