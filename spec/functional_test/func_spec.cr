require "spec" # Make spec DSL available
require "../../src/models/noir.cr"
require "../../src/models/endpoint.cr"
require "../../src/config_initializer.cr" # Added to define ConfigInitializer

module Noir
  VERSION = "SPEC"
end

class FunctionalTester
  # expected_count's symbols are:
  # :techs
  # :endpoints
  @expected_count : Hash(Symbol, Int32)
  @expected_endpoints : Array(Endpoint)
  @app : NoirRunner
  @path : String

  def initialize(@path, expected_count, expected_endpoints)
    config_init = ConfigInitializer.new
    noir_options = config_init.default_options
    noir_options["base"] = YAML::Any.new("./spec/functional_test/#{@path}")
    noir_options["nolog"] = YAML::Any.new(true)

    if !expected_count.nil?
      @expected_count = expected_count
    else
      @expected_count = Hash(Symbol, Int32).new
    end

    if !expected_endpoints.nil?
      @expected_endpoints = expected_endpoints
    else
      @expected_endpoints = Array(Endpoint).new
    end

    @app = NoirRunner.new noir_options
  end

  def test_detect
    @app.detect
    if @expected_count.has_key?(:techs)
      it "test detect using count check" do
        @app.techs.size.should eq @expected_count[:techs]
      end
    end
  end

  def find_endpoint(key)
    @expected_endpoints.each do |endpoint|
      expected_key = endpoint.method.to_s + "::" + endpoint.url.to_s
      if expected_key.to_s == key.to_s
        return endpoint
      end
    end
    nil
  end

  def find_param(param_name)
    if @expected_endpoints.params.size > 0
      @expected_endpoints.params.each do |param|
        if param.name.to_s == param_name.to_s
          return param
        end
      end
    end

    nil
  end

  def test_analyze
    @app.analyze
    if @expected_count.has_key?(:endpoints)
      it "test analyze using count check" do
        @app.endpoints.size.should eq @expected_count[:endpoints]
      end
    end

    if @expected_endpoints.size > 0
      @app.endpoints.each do |endpoint|
        key = endpoint.method.to_s + "::" + endpoint.url.to_s
        found_endpoint = find_endpoint key
        if found_endpoint.nil?
          it "endpoint [#{key}] not found" do
            false.should eq true
          end
        else
          describe "endpoint check [#{key}]" do
            it "check - url [K: #{key}]" do
              endpoint.url.should eq found_endpoint.url
            end

            it "check - method [K: #{key}]" do
              endpoint.method.should eq found_endpoint.method
            end

            if endpoint.params.size > 0
              describe "check - params" do
                endpoint.params.each do |param|
                  found_params = found_endpoint.params.select { |found_p| found_p.name == param.name }
                  if found_params.size == 0
                    it "params nil" do
                      false.should eq true
                    end
                  else
                    it "check '#{param.name}' name " do
                      param.name.should eq found_params[0].name
                    end
                    it "check '#{param.name}' param_type '#{param.param_type}'" do
                      (found_params.any? { |found_p| found_p.param_type == param.param_type }).should be_true
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  def perform_tests
    # Describe block removed from here
    locator = CodeLocator.instance
    locator.clear_all
    test_detect
    test_analyze
  end

  def app
    @app
  end

  def url=(url)
    @app.options["url"] = YAML::Any.new(url)
  end
end

describe "Elixir Phoenix framework with input detection" do
  it "should detect parameters, headers, and cookies" do
    noir = Noir::Scanner.new("./spec/functional_test/fixtures/elixir/phoenix")
    noir.scan
    results = noir.result

    # Test case 1: params_in_signature
    endpoint1 = results.find { |e| e.url == "/input_test/params_in_signature/:user_id" && e.method == "GET" }
    endpoint1.should_not be_nil
    endpoint1.as(Endpoint).params.any? { |p| p.name == "user_id" && p.param_type == "query" }.should be_true
    endpoint1.as(Endpoint).params.any? { |p| p.name == "type" && p.param_type == "query" }.should be_true
    endpoint1.as(Endpoint).details.code_paths.first.path.should contain("input_test_controller.ex") # Path check
    endpoint1.as(Endpoint).details.code_paths.first.line.should eq(15) # Line of the route definition in router.ex

    # Test case 2: headers_test
    endpoint2 = results.find { |e| e.url == "/input_test/headers_test" && e.method == "GET" }
    endpoint2.should_not be_nil
    endpoint2.as(Endpoint).params.any? { |p| p.name == "user-agent" && p.param_type == "header" }.should be_true
    endpoint2.as(Endpoint).params.any? { |p| p.name == "authorization" && p.param_type == "header" }.should be_true
    endpoint2.as(Endpoint).params.any? { |p| p.name == "x-custom-header" && p.param_type == "header" }.should be_true
    endpoint2.as(Endpoint).details.code_paths.first.line.should eq(16) # Line of the route definition


    # Test case 3: cookies_test
    endpoint3 = results.find { |e| e.url == "/input_test/cookies_test" && e.method == "POST" }
    endpoint3.should_not be_nil
    endpoint3.as(Endpoint).params.any? { |p| p.name == "session_id" && p.param_type == "cookie" }.should be_true
    endpoint3.as(Endpoint).params.any? { |p| p.name == "tracker_id" && p.param_type == "cookie" }.should be_true
    endpoint3.as(Endpoint).details.code_paths.first.line.should eq(17) # Line of the route definition


    # Test case 4: mixed_input
    endpoint4 = results.find { |e| e.url == "/input_test/mixed_input/:item_id" && e.method == "GET" }
    endpoint4.should_not be_nil
    endpoint4.as(Endpoint).params.any? { |p| p.name == "item_id" && p.param_type == "query" }.should be_true
    endpoint4.as(Endpoint).params.any? { |p| p.name == "filter" && p.param_type == "query" }.should be_true
    endpoint4.as(Endpoint).params.any? { |p| p.name == "x-auth-token" && p.param_type == "header" }.should be_true
    endpoint4.as(Endpoint).params.any? { |p| p.name == "user_preference" && p.param_type == "cookie" }.should be_true
    endpoint4.as(Endpoint).details.code_paths.first.line.should eq(18) # Line of the route definition


    # Test case 5: no_specific_inputs
    endpoint5 = results.find { |e| e.url == "/input_test/no_specific_inputs" && e.method == "GET" }
    endpoint5.should_not be_nil
    endpoint5.as(Endpoint).params.empty?.should be_true # No specific params, headers, cookies expected
    endpoint5.as(Endpoint).details.code_paths.first.line.should eq(19) # Line of the route definition
  end
end
