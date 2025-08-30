require "../../spec_helper"
require "../../../src/optimizer/llm_optimizer"
require "../../../src/options"
require "../../../src/models/endpoint"
require "../../../src/models/logger"

describe "LLMEndpointOptimizer" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  logger = NoirLogger.new(false, false, false, false)

  describe "initialization without LLM config" do
    it "creates optimizer without LLM capabilities" do
      optimizer = LLMEndpointOptimizer.new(logger, options)
      # Should not crash and work as base optimizer
      endpoints = [Endpoint.new("/test", "GET")]
      result = optimizer.optimize(endpoints)
      result.size.should eq(1)
    end
  end

  describe "integration with base optimizer" do
    it "runs standard optimization when LLM is disabled" do
      optimizer = LLMEndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/users/{id}", "GET"),
        Endpoint.new("users/{id}", "GET"), # duplicate
      ]

      result = optimizer.optimize(endpoints)
      result.size.should eq(1) # Should deduplicate
      result[0].url.should eq("/users/{id}")
      result[0].params.size.should eq(1) # Should extract path parameter
    end
  end

  describe "full workflow without LLM" do
    it "works as standard optimizer when no LLM config" do
      options["url"] = YAML::Any.new("https://test.com")
      optimizer = LLMEndpointOptimizer.new(logger, options)

      endpoints = [
        Endpoint.new("/users/{id}", "GET"),
        Endpoint.new("//users//{id}", "GET"), # duplicate with extra slashes
        Endpoint.new("/posts/:post_id", "POST"),
      ]

      result = optimizer.optimize(endpoints)

      # Should work like base optimizer
      result.size.should eq(2) # Deduplicated
      result[0].url.should eq("https://test.com/users/{id}")
      result[1].url.should eq("https://test.com/posts/:post_id")

      # Should extract parameters
      result[0].params.size.should eq(1)
      result[1].params.size.should eq(1)
    end
  end

  describe "handles non-standard patterns without LLM" do
    it "processes wildcard patterns safely" do
      options["url"] = YAML::Any.new("") # No base URL for this test
      optimizer = LLMEndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/api/*/data", "GET"),
        Endpoint.new("/api/users_data__special", "GET"),
      ]

      result = optimizer.optimize(endpoints)
      result.size.should eq(2)
      result[0].url.should eq("/api/*/data")
      result[1].url.should eq("/api/users_data__special")
    end
  end

  describe "inherits all base functionality" do
    it "applies pvalue configurations" do
      options["set_pvalue"] = YAML::Any.new([YAML::Any.new("id=TEST_ID")])
      optimizer = LLMEndpointOptimizer.new(logger, options)

      result = optimizer.apply_pvalue("path", "id", "original")
      result.should eq("TEST_ID")
    end

    it "combines URLs correctly" do
      options["url"] = YAML::Any.new("https://api.test.com")
      optimizer = LLMEndpointOptimizer.new(logger, options)
      endpoints = [Endpoint.new("/users", "GET")]

      result = optimizer.combine_url_and_endpoints(endpoints)
      result[0].url.should eq("https://api.test.com/users")
    end

    it "extracts path parameters" do
      optimizer = LLMEndpointOptimizer.new(logger, options)
      endpoints = [Endpoint.new("/users/{id}/posts/<int:post_id>", "GET")]

      result = optimizer.add_path_parameters(endpoints)
      result[0].params.size.should eq(2)
      result[0].params[0].name.should eq("id")
      result[0].params[1].name.should eq("post_id")
    end
  end

  describe "handles complex optimization scenarios" do
    it "processes mixed parameter patterns" do
      options["url"] = YAML::Any.new("https://api.example.com")
      options["set_pvalue"] = YAML::Any.new([YAML::Any.new("user_id=123"), YAML::Any.new("post_id=456")])
      optimizer = LLMEndpointOptimizer.new(logger, options)

      endpoints = [
        Endpoint.new("/users/{user_id}", "GET"),
        Endpoint.new("/users/:user_id/posts/<int:post_id>", "GET"),
        Endpoint.new("//users//{user_id}", "GET"), # exact duplicate with slashes
      ]

      result = optimizer.optimize(endpoints)

      # Should have 2 unique endpoints after optimization
      result.size.should eq(2)

      # All should have proper base URL
      result.each do |endpoint|
        endpoint.url.should contain("https://api.example.com")
      end

      # Should extract all parameters
      result[0].params.size.should eq(1)
      result[1].params.size.should eq(2)
    end
  end
end
