require "../../func_spec.cr"

describe "FeignClient Analysis" do
  it "should detect FeignClient endpoints with --analyze-feign flag" do
    # Setup options with analyze_feign enabled
    config_init = ConfigInitializer.new
    noir_options = config_init.default_options
    noir_options["base"] = YAML::Any.new("./spec/functional_test/fixtures/java/spring/")
    noir_options["nolog"] = YAML::Any.new(true)
    noir_options["analyze_feign"] = YAML::Any.new(true)

    app = NoirRunner.new noir_options
    app.detect
    app.analyze

    # Check that FeignClient endpoints are detected
    feign_endpoints = app.endpoints.select { |endpoint| endpoint.url.includes?("/api/v2") }
    feign_endpoints.size.should eq 4

    # Check that FeignClient endpoints are marked as internal
    feign_endpoints.each do |endpoint|
      endpoint.internal.should eq true
    end

    # Check specific endpoints
    patch_endpoint = feign_endpoints.find { |e| e.method == "PATCH" && e.url == "/api/v2/items/{id}/stock" }
    patch_endpoint.should_not be_nil
    if patch_endpoint
      patch_endpoint.params.size.should eq 2
      patch_endpoint.params.any? { |p| p.name == "id" && p.param_type == "path" }.should be_true
      patch_endpoint.params.any? { |p| p.name == "quantity" && p.param_type == "json" }.should be_true
    end
  end

  it "should NOT detect FeignClient endpoints without --analyze-feign flag" do
    # Setup options without analyze_feign flag
    config_init = ConfigInitializer.new
    noir_options = config_init.default_options
    noir_options["base"] = YAML::Any.new("./spec/functional_test/fixtures/java/spring/")
    noir_options["nolog"] = YAML::Any.new(true)
    # analyze_feign defaults to false

    app = NoirRunner.new noir_options
    app.detect
    app.analyze

    # Check that FeignClient endpoints are NOT detected
    feign_endpoints = app.endpoints.select { |endpoint| endpoint.url.includes?("/api/v2") }
    feign_endpoints.size.should eq 0
  end
end