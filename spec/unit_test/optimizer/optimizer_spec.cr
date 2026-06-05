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

    it "preserves ANY as a valid HTTP method" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/test", "ANY"),
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result[0].method.should eq("ANY")
    end

    it "canonicalizes valid methods to upper case" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/test", "get"),
        Endpoint.new("/test", "Post"),
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result.map(&.method).should eq(["GET", "POST"])
    end

    it "deduplicates endpoints whose methods differ only in case" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/api/users", "get"),
        Endpoint.new("/api/users", "GET"), # same endpoint, different casing
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result.size.should eq(1)
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

    it "does not corrupt absolute URLs while normalizing slashes" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("https://api.example.com/v1/users", "GET"),
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result[0].url.should eq("https://api.example.com/v1/users")
    end

    it "collapses path slashes without touching an embedded URL in the query" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        # The double slash in `https://` inside the query value must
        # survive; only the redundant `//` in the path is collapsed.
        Endpoint.new("//auth//callback?redirect_uri=https://app.example/cb", "GET"),
      ]

      result = optimizer.optimize_endpoints(endpoints)
      result[0].url.should eq("/auth/callback?redirect_uri=https://app.example/cb")
    end

    it "strips Spring inline regex constraints from path variables" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/users/{id:[0-9]+}", "GET"),
        Endpoint.new("/files/{path:.*}", "GET"),
        Endpoint.new("/a/{x:[^/]+}/b/{y}", "GET"),
      ]

      result = optimizer.normalize_url_shapes(endpoints)
      result[0].url.should eq("/users/{id}")
      result[1].url.should eq("/files/{path}")
      result[2].url.should eq("/a/{x}/b/{y}")
    end

    it "normalizes Django re_path named groups even when the body contains \\d / \\w classes" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/(?P<organization_slug>[^/]+)/issues/(?P<group_id>\\d+)/", "GET"),
        Endpoint.new("/api/0/(?P<event_id>[A-Fa-f0-9-]{32,36})/", "GET"),
      ]

      result = optimizer.normalize_url_shapes(endpoints)
      result[0].url.should eq("/{organization_slug}/issues/{group_id}/")
      result[1].url.should eq("/api/0/{event_id}/")
    end

    it "still skips verbatim Express regex-literal routes" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/^\\/api\\/(\\d+)$/", "GET"),
      ]

      result = optimizer.normalize_url_shapes(endpoints)
      result[0].url.should eq("/^\\/api\\/(\\d+)$/")
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

    it "strips the target only as a leading prefix, not inside query values" do
      options["url"] = YAML::Any.new("https://example.com")
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        # The target host appears in a query value, not as a prefix — a
        # blanket gsub would drop it and corrupt the redirect target.
        Endpoint.new("/proxy?next=https://example.com/login", "GET"),
        # Already-prefixed endpoint should be de-duplicated to a single prefix.
        Endpoint.new("https://example.com/api/users", "GET"),
      ]

      result = optimizer.combine_url_and_endpoints(endpoints)
      result[0].url.should eq("https://example.com/proxy?next=https://example.com/login")
      result[1].url.should eq("https://example.com/api/users")
    end

    it "passes through absolute endpoint URLs on a different host" do
      options["url"] = YAML::Any.new("https://example.com")
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("https://cdn.other.com/assets/app.js", "GET"),
      ]

      result = optimizer.combine_url_and_endpoints(endpoints)
      # The scheme `//` must survive (no collapse) and the target must
      # not be prepended onto a self-contained absolute URL.
      result[0].url.should eq("https://cdn.other.com/assets/app.js")
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

    it "extracts every variable from a comma-packed segment" do
      optimizer = EndpointOptimizer.new(logger, options)
      # Spring's matrix-style mapping packs sibling path variables into one
      # segment separated by commas (e.g.
      # @GetMapping("/bbox/{xMin},{yMin},{xMax},{yMax}")). Each is a path
      # param; only the first used to be captured.
      endpoints = [
        Endpoint.new("/bbox/{xMin},{yMin},{xMax},{yMax}", "GET"),
        Endpoint.new("/user/{userName}/location/{x},{y}", "PUT"),
      ]

      result = optimizer.add_path_parameters(endpoints)
      result[0].params.map(&.name).should eq(["xMin", "yMin", "xMax", "yMax"])
      result[0].params.all? { |p| p.param_type == "path" }.should be_true
      result[1].params.map(&.name).should eq(["userName", "x", "y"])
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

    it "does not duplicate a path param the analyzer already recorded with a type" do
      optimizer = EndpointOptimizer.new(logger, options)
      # Haskell's Servant/Yesod analyzers store the captured type in the param
      # `value` (e.g. `Capture "id" Int`). The URL-derived param has an empty
      # value, so an exact-struct dedup used to miss it and add a duplicate.
      endpoints = [
        Endpoint.new("/users/:id", "GET", [Param.new("id", "Int", "path")]),
        Endpoint.new("/sites/{site_id}", "GET", [Param.new("site_id", "SiteId", "path")]),
        Endpoint.new("/files/*path", "GET", [Param.new("path", "Text", "path")]),
      ]

      result = optimizer.add_path_parameters(endpoints)
      result.each do |endpoint|
        path_params = endpoint.params.select { |param| param.param_type == "path" }
        path_params.size.should eq(1)
        # The analyzer-supplied type must survive (no empty-value clobber).
        path_params[0].value.should_not eq("")
      end
    end

    it "reconciles ruby path params against same-named query/body params" do
      optimizer = EndpointOptimizer.new(logger, options)
      ruby_details = Details.new
      ruby_details.technology = "ruby_rails"
      other_details = Details.new
      other_details.technology = "lucky"

      endpoints = [
        # Rack frameworks merge path captures into params, so the body
        # `params[:id]` for /users/:id IS the path value — drop the query dup.
        Endpoint.new("/users/:id", "GET", [Param.new("id", "", "query"), Param.new("token", "", "query")], ruby_details),
        # Non-ruby (Lucky) keeps separate typed path/query buckets — keep both.
        Endpoint.new("/users/:id", "GET", [Param.new("id", "", "query")], other_details),
      ]

      result = optimizer.add_path_parameters(endpoints)

      ruby_params = result[0].params
      ruby_params.count { |p| p.name == "id" }.should eq(1)
      ruby_params.find! { |p| p.name == "id" }.param_type.should eq("path")
      ruby_params.any? { |p| p.name == "token" && p.param_type == "query" }.should be_true

      result[1].params.count { |p| p.name == "id" }.should eq(2) # path + query both kept
    end

    it "names catch-all path variables without the leading asterisk" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/files/{*path}", "GET"), # Spring / Armeria / ASP.NET
        Endpoint.new("/static/{*remaining}/raw", "GET"),
      ]

      result = optimizer.add_path_parameters(endpoints)
      result[0].params.size.should eq(1)
      result[0].params[0].name.should eq("path")
      result[0].params[0].param_type.should eq("path")

      result[1].params.size.should eq(1)
      result[1].params[0].name.should eq("remaining")
    end

    it "ignores bare glob splats that are not real parameter names" do
      optimizer = EndpointOptimizer.new(logger, options)
      endpoints = [
        Endpoint.new("/glob/**", "GET"),      # Armeria glob: captures `*`, not a name
        Endpoint.new("/assets/*file", "GET"), # named splat is still a parameter
      ]

      result = optimizer.add_path_parameters(endpoints)
      result[0].params.size.should eq(0)

      result[1].params.size.should eq(1)
      result[1].params[0].name.should eq("file")
      result[1].params[0].param_type.should eq("path")
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
