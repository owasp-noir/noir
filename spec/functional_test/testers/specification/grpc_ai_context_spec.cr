require "../../func_spec.cr"

describe "--ai-context on gRPC fixtures", tags: "functional" do
  fixture_path = "fixtures/specification/grpc/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "does not apply HTTP mutation or rich-content heuristics to pure RPCs" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints
    [
      "/HealthService/Check",
      "/example.v1.UserService/ListUsers",
      "/example.v1.UserService/StreamUsers",
      "/comments.v1.NoteService/CreateNote",
    ].each do |url|
      endpoint = endpoints.find! { |candidate| candidate.url == url }
      endpoint.protocol.should eq("grpc")

      context = endpoint.ai_context.should_not be_nil
      signal_kinds = context.signals.map(&.kind)
      signal_kinds.should_not contain("state_change")
      signal_kinds.should_not contain("guard_absence")
    end

    create_note = endpoints.find! { |candidate| candidate.url == "/comments.v1.NoteService/CreateNote" }
    create_note.ai_context.should_not be_nil
    create_note.ai_context.not_nil!.signals.map(&.kind).should_not contain("html_content_input")

    gateway_create = endpoints.find! { |candidate| candidate.url == "/api/v1/users" && candidate.protocol == "http" }
    gateway_create.ai_context.should_not be_nil
    gateway_create.ai_context.not_nil!.signals.map(&.kind).should contain("state_change")
  end
end
