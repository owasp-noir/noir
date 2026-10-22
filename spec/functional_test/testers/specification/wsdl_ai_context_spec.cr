require "../../func_spec.cr"

describe "--ai-context on WSDL fixtures", tags: "functional" do
  fixture_path = "fixtures/specification/wsdl/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "uses SOAP operation intent instead of treating every POST as a mutation" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    ["GetUser", "ListUsers", "FindUser"].each do |operation|
      endpoint = app.endpoints.find!(&.url.ends_with?("/#{operation}"))
      context = endpoint.ai_context.should_not be_nil
      signal_kinds = context.signals.map(&.kind)
      signal_kinds.should_not contain("state_change")
      signal_kinds.should_not contain("guard_absence")
    end

    create_user = app.endpoints.find!(&.url.ends_with?("/CreateUser"))
    create_user_context = create_user.ai_context.should_not be_nil
    create_user_signals = create_user_context.signals.map(&.kind)
    create_user_signals.should contain("state_change")
    create_user_signals.should contain("guard_absence")
  end
end
