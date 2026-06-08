require "../../func_spec.cr"

describe "actix builder local handler shadowing" do
  it "does not attach params from a same-named handler in another file" do
    config_init = ConfigInitializer.new
    options = config_init.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/rust/actix_builder_local_shadow/")])
    options["nolog"] = YAML::Any.new(true)
    options["only_techs"] = YAML::Any.new("rust_actix_web")

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find { |e| e.method == "POST" && e.url == "/local" }
    endpoint.should_not be_nil
    endpoint.not_nil!.params.should be_empty
  end
end
