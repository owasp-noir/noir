require "../../func_spec.cr"

describe "--ai-context Hunt signals on Fastify fixtures" do
  fixture_path = "fixtures/javascript/fastify/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "avoids broad Hunt false positives on common body and view fields" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints

    register_context = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/register" }.ai_context
    register_context = register_context.should_not be_nil
    register_context.signals.map(&.kind).should_not contain("idor")

    product_context = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/products" }.ai_context
    product_context = product_context.should_not be_nil
    product_context.signals.map(&.kind).should_not contain("ssti")
    product_context.signals.map(&.kind).should_not contain("sqli")

    dashboard_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/dashboard" }.ai_context
    dashboard_context = dashboard_context.should_not be_nil
    dashboard_context.signals.map(&.kind).should_not contain("ssti")
    dashboard_context.signals.map(&.kind).should_not contain("ssrf")
    dashboard_context.signals.map(&.kind).should_not contain("sqli")

    admin_create_context = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/admin/users/create" }.ai_context
    admin_create_context = admin_create_context.should_not be_nil
    admin_create_context.signals.map(&.kind).should_not contain("sqli")

    process_context = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/payments/process/:methodId" }.ai_context
    process_context = process_context.should_not be_nil
    process_context.signals.map(&.kind).should contain("path_param")
    process_context.signals.map(&.kind).should contain("idor")
    process_context.signals.map(&.kind).should contain("idor_review")
    process_context.signals.map(&.kind).should_not contain("guard_absence")

    upload_context = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/upload" }.ai_context
    upload_context = upload_context.should_not be_nil
    upload_context.signals.map(&.kind).should_not contain("file_input")
  end
end
