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
      it "test detect using count check [#{@path}]" do
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
      it "test analyze using count check [#{@path}]" do
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

describe "Functional Test" do
  # Java
  tester_java_spring_feign = FunctionalTester.new(
    "fixtures/java/spring_feign",
    {:techs => 1, :endpoints => 2},
    [
      Endpoint.new("http://inventory-service/api/v2/items/{id}/stock", "PATCH"),
      Endpoint.new("http://inventory-service/api/v2/items", "GET"),
    ]
  )
  tester_java_spring_feign.app.options["analyze_feign_clients"] = YAML::Any.new(true)
  tester_java_spring_feign.perform_tests
end
