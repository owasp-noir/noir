require "../../func_spec.cr"

# PHP's other process launchers (`shell_exec`, `passthru`, `proc_open`) run a
# command as `exec` / `system` do, and Laravel's `DB::raw` / `...Raw` builder
# methods take SQL text as written.
describe "Laravel sink shapes", tags: "functional" do
  fixture = "./spec/functional_test/fixtures/php/laravel_sink_shapes/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "reports command execution and raw SQL sinks" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new(fixture)])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    sinks = ->(url : String) do
      app.endpoints.find! { |ep| ep.url == url }.ai_context.try(&.sinks.map(&.kind)) || [] of String
    end

    sinks.call("/tools/run").should contain("command_exec")
    sinks.call("/tools/stream").should contain("command_exec")
    sinks.call("/tools/spawn").should contain("command_exec")
    sinks.call("/reports/totals").should contain("sql")
    sinks.call("/reports/scoped").should contain("sql")

    sinks.call("/reports/plain").should_not contain("command_exec")
    sinks.call("/reports/plain").should_not contain("sql")
  end
end
