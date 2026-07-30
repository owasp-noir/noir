require "../../spec_helper"
require "../../../src/optimizer/llm_optimizer"
require "../../../src/models/endpoint"
require "../../../src/models/logger"
require "file_utils"

# Expose the private LLM-response application path so the FP/FN guards
# on the correction step can be tested without a live adapter.
class LLMEndpointOptimizer
  def __test_apply(endpoint : Endpoint, response : String) : Endpoint
    apply_llm_optimizations(endpoint, response)
  end

  def __test_adapter : LLM::Adapter?
    @adapter
  end

  def __test_install_adapter(adapter : LLM::Adapter, provider : String, model : String) : Nil
    @adapter = adapter
    @provider = provider
    @model = model
    @use_llm = true
  end

  def __test_request(prompt : String) : String
    request_optimization(prompt, @adapter.as(LLM::Adapter))
  end
end

class LLM::General
  def __test_api_key : String?
    @api_key
  end
end

# Counts requests so cache hits are observable without a live provider.
class CountingAdapter
  include LLM::Adapter

  getter calls : Int32 = 0

  def initialize(@payload : String)
  end

  def request(prompt : String, format : String = "json") : String
    @calls += 1
    @payload
  end

  def request_messages(messages : LLM::Adapter::Messages, format : String = "json") : String
    request("", format)
  end
end

private def with_isolated_cache_dir(&)
  prev_home = ENV["NOIR_HOME"]?
  prev_disable = ENV["NOIR_CACHE_DISABLE"]?
  tmp = File.tempname("noir-llm-optimizer-spec")
  Dir.mkdir_p(tmp)
  ENV["NOIR_HOME"] = tmp
  ENV.delete("NOIR_CACHE_DISABLE")
  begin
    LLM::Cache.enable
    yield
  ensure
    if prev_home
      ENV["NOIR_HOME"] = prev_home
    else
      ENV.delete("NOIR_HOME")
    end
    if prev_disable
      ENV["NOIR_CACHE_DISABLE"] = prev_disable
    else
      ENV.delete("NOIR_CACHE_DISABLE")
    end
    FileUtils.rm_rf(tmp)
  end
end

private def with_ai_key_env(value : String?, &)
  prev = ENV["NOIR_AI_KEY"]?
  if value
    ENV["NOIR_AI_KEY"] = value
  else
    ENV.delete("NOIR_AI_KEY")
  end
  begin
    yield
  ensure
    if prev
      ENV["NOIR_AI_KEY"] = prev
    else
      ENV.delete("NOIR_AI_KEY")
    end
  end
end

describe "LLMEndpointOptimizer" do
  options = create_test_options
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

  describe "LLM response correction guards" do
    guard_logger = NoirLogger.new(false, false, false, false)

    it "applies a clean URL rewrite and drops garbage params" do
      optimizer = LLMEndpointOptimizer.new(guard_logger, create_test_options)
      endpoint = Endpoint.new("/users/USR123", "GET")
      response = %({"optimized_url":"/users/{id}","optimized_params":[{"name":"id","param_type":"path","value":""},{"name":"bad name","param_type":"query","value":""}]})

      result = optimizer.__test_apply(endpoint, response)
      result.url.should eq("/users/{id}")
      result.params.map(&.name).should eq(["id"])
    end

    it "rejects a corrupting URL rewrite that leaks whitespace" do
      optimizer = LLMEndpointOptimizer.new(guard_logger, create_test_options)
      endpoint = Endpoint.new("/users/{id}", "GET")
      response = %({"optimized_url":"/GET /users/{id}","optimized_params":[]})

      result = optimizer.__test_apply(endpoint, response)
      result.url.should eq("/users/{id}")
    end
  end

  describe "adapter configuration" do
    it "treats an empty ai_key as absent so NOIR_AI_KEY still applies" do
      llm_options = create_test_options
      llm_options["ai_provider"] = YAML::Any.new("openai")
      llm_options["ai_model"] = YAML::Any.new("gpt-4o-mini")
      llm_options["ai_key"] = YAML::Any.new("")

      with_ai_key_env("env-key") do
        optimizer = LLMEndpointOptimizer.new(logger, llm_options)
        adapter = optimizer.__test_adapter.as(LLM::GeneralAdapter)
        adapter.client.__test_api_key.should eq("env-key")
      end
    end

    it "stays disabled without an AI provider" do
      LLMEndpointOptimizer.new(logger, create_test_options).__test_adapter.should be_nil
    end
  end

  describe "response caching" do
    it "reuses a cached correction instead of re-billing the provider" do
      with_isolated_cache_dir do
        optimizer = LLMEndpointOptimizer.new(logger, create_test_options)
        adapter = CountingAdapter.new(%({"optimized_url":"/users/{id}","optimized_params":[]}))
        optimizer.__test_install_adapter(adapter, "openai", "gpt-4o-mini")

        first = optimizer.__test_request("prompt A")
        second = optimizer.__test_request("prompt A")

        first.should eq(second)
        adapter.calls.should eq(1)
      end
    end

    it "keys on the prompt so different endpoints are not conflated" do
      with_isolated_cache_dir do
        optimizer = LLMEndpointOptimizer.new(logger, create_test_options)
        adapter = CountingAdapter.new(%({"optimized_url":"/users/{id}","optimized_params":[]}))
        optimizer.__test_install_adapter(adapter, "openai", "gpt-4o-mini")

        optimizer.__test_request("prompt A")
        optimizer.__test_request("prompt B")

        adapter.calls.should eq(2)
      end
    end

    it "does not cache a failed request" do
      with_isolated_cache_dir do
        optimizer = LLMEndpointOptimizer.new(logger, create_test_options)
        adapter = CountingAdapter.new("")
        optimizer.__test_install_adapter(adapter, "openai", "gpt-4o-mini")

        optimizer.__test_request("prompt A")
        optimizer.__test_request("prompt A")

        adapter.calls.should eq(2)
      end
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
