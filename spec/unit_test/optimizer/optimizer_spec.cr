require "../../spec_helper"
require "../../../src/optimizer/optimizer"
require "../../../src/models/endpoint"
require "../../../src/models/logger"

describe "EndpointOptimizer" do
  options = create_test_options
  logger = NoirLogger.new(false, false, false, false)

  describe "optimize_endpoints" do
    it "removes duplicated endpoints" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/api/users", "GET"),
        Endpoint.new("/api/users", "GET"), # duplicate
        Endpoint.new("/api/users", "POST"),
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result.size.should eq(2)
      result[0].method.should eq("GET")
      result[1].method.should eq("POST")
    end

    it "normalizes HTTP methods" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/test", "INVALID_METHOD"),
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result[0].method.should eq("GET")
    end

    it "normalizes URLs with slashes" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("api/users", "GET"),   # missing leading slash
        Endpoint.new("//api//data", "GET"), # double slashes
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result[0].url.should eq("/api/users")
      result[1].url.should eq("/api/data")
    end
  end

  describe "combine_url_and_endpoints" do
    it "combines target URL with endpoints" do
      options["url"] = YAML::Any.new("https://example.com")
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/api/users", "GET"),
        Endpoint.new("api/data", "POST"),
      ]

      result = optimizer.combine_url_and_endpoints(endpoints)
      result[0].url.should eq("https://example.com/api/users")
      result[1].url.should eq("https://example.com/api/data")
    end

    it "returns unchanged endpoints when no target URL" do
      options["url"] = YAML::Any.new("")
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/api/users", "GET"),
      ]

      result = optimizer.combine_url_and_endpoints(endpoints)
      result[0].url.should eq("/api/users")
    end
  end

  describe "add_path_parameters" do
    it "extracts parameters from curly brace patterns" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/users/{id}", "GET"),
        Endpoint.new("/posts/{id}/comments/{comment_id}", "GET"),
      ]

      result = optimizer.add_path_parameters(endpoints)
      result[0].params.size.should eq(1)
      result[0].params[0].name.should eq("id")
      result[0].params[0].param_type.should eq("path")

      result[1].params.size.should eq(2)
      result[1].params[0].name.should eq("id")
      result[1].params[1].name.should eq("comment_id")
    end

    it "extracts parameters from colon patterns" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/users/:id", "GET"),
        Endpoint.new("/posts/:post_id/edit", "GET"),
      ]

      result = optimizer.add_path_parameters(endpoints)
      result[0].params.size.should eq(1)
      result[0].params[0].name.should eq("id")

      result[1].params.size.should eq(1)
      result[1].params[0].name.should eq("post_id")
    end

    it "extracts parameters from angle bracket patterns" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/users/<id>", "GET"),
        Endpoint.new("/posts/<int:post_id>", "GET"), # Django style
        Endpoint.new("/items/<name:str>", "GET"),    # Marten style
      ]

      result = optimizer.add_path_parameters(endpoints)
      result[0].params.size.should eq(1)
      result[0].params[0].name.should eq("id")

      result[1].params.size.should eq(1)
      result[1].params[0].name.should eq("post_id")

      result[2].params.size.should eq(1)
      result[2].params[0].name.should eq("name")
    end
  end

  describe "apply_pvalue" do
    it "applies configured parameter values" do
      options["set_pvalue"] = YAML::Any.new([YAML::Any.new("name=FUZZ")])
      optimizer = EndpointOptimizer.new(logger, options)

      result = optimizer.apply_pvalue("query", "name", "original")
      result.should eq("FUZZ")
    end

    it "returns original value when no configuration matches" do
      options["set_pvalue"] = YAML::Any.new([] of YAML::Any)
      optimizer = EndpointOptimizer.new(logger, options)

      result = optimizer.apply_pvalue("query", "unknown", "original")
      result.should eq("original")
    end
  end

  describe "full optimization workflow" do
    it "runs complete optimization pipeline" do
      options["url"] = YAML::Any.new("https://api.example.com")
      options["set_pvalue"] = YAML::Any.new([YAML::Any.new("id=123")])
      optimizer = EndpointOptimizer.new(logger, options)

      endpoints = [
        Endpoint.new("/users/{id}", "GET"),
        Endpoint.new("users/{id}", "GET"), # duplicate with different slash
        Endpoint.new("/posts/:post_id", "POST"),
      ]

      result = optimizer.optimize(endpoints)

      # Should have 2 unique endpoints after deduplication
      result.size.should eq(2)

      # URLs should be combined with target URL
      result[0].url.should contain("https://api.example.com")
      result[1].url.should contain("https://api.example.com")

      # Parameters should be extracted
      result[0].params.size.should eq(1)
      result[0].params[0].name.should eq("id")
      result[0].params[0].param_type.should eq("path")

      result[1].params.size.should eq(1)
      result[1].params[0].name.should eq("post_id")
      result[1].params[0].param_type.should eq("path")
    end
  end
end
