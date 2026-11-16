require "../../func_spec.cr"

# Ruby runs a backtick or `%x` literal as a shell command, and an ActiveRecord
# query method given an interpolated string sends that text as SQL. A bound
# placeholder (`where("x LIKE ?", v)`) and a backtick inside a message string
# do neither.
describe "Rails sink shapes", tags: "functional" do
  fixture = "./spec/functional_test/fixtures/ruby/rails_sink_shapes/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "reports interpolated SQL fragments and command literals" do
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

    sinks.call("/reports").should contain("sql")
    sinks.call("/reports/ordered").should contain("sql")
    sinks.call("/reports/notify").should contain("command_exec")
    sinks.call("/reports/convert").should contain("command_exec")

    sinks.call("/reports/safe").should_not contain("sql")
    sinks.call("/reports/safe").should_not contain("command_exec")
  end
end
