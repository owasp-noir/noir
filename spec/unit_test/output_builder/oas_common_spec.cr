require "../../spec_helper"
require "../../../src/output_builder/oas_common"

private struct OasCommonTestHelper
  include OutputBuilderOasCommon

  def test_normalize_oas_path(raw_url : String, declared_path_params : Array(String) = [] of String)
    normalize_oas_path(raw_url, declared_path_params)
  end

  def test_extract_unmapped_path_parameters(parameters : Array(Hash(String, JSON::Any)), template_names : Array(String))
    extract_unmapped_path_parameters(parameters, template_names)
  end

  def test_path_template_names(path : String)
    path_template_names(path)
  end

  def test_operation_methods(method : String)
    operation_methods(method)
  end

  def test_swagger_url_parts(raw_url : String)
    swagger_url_parts(raw_url)
  end
end

describe OutputBuilderOasCommon do
  helper = OasCommonTestHelper.new

  describe "#normalize_oas_path" do
    it "normalizes express style optional segments and param syntax" do
      helper.test_normalize_oas_path("/users/:id").should eq("/users/{id}")
      helper.test_normalize_oas_path("/users/[id]").should eq("/users/{id}")
      helper.test_normalize_oas_path("/users/<int:id>").should eq("/users/{id}")
      helper.test_normalize_oas_path("/users/*id").should eq("/users/{id}")
      helper.test_normalize_oas_path("/files/*").should eq("/files/{wildcard}")
    end

    it "names each bare wildcard distinctly" do
      # A path template variable may not repeat, so `/api/*/v1/*` cannot emit
      # `{wildcard}` twice.
      helper.test_normalize_oas_path("/api/*/v1/*").should eq("/api/{wildcard}/v1/{wildcard2}")
    end

    it "resolves name-first typed placeholders" do
      # Sanic / Bottle / Marten spell the placeholder `<name:type>`, the
      # reverse of Django / Flask's `<type:name>`.
      helper.test_normalize_oas_path("/users/<id:int>").should eq("/users/{id}")
      helper.test_normalize_oas_path("/posts/<post_id:uuid>").should eq("/posts/{post_id}")
      helper.test_normalize_oas_path("/n/<int(min=1):page>").should eq("/n/{page}")
    end

    it "prefers the endpoint's declared path params for typed placeholders" do
      helper.test_normalize_oas_path("/a/<foo:bar>", ["bar"]).should eq("/a/{bar}")
      helper.test_normalize_oas_path("/a/<foo:bar>", ["foo"]).should eq("/a/{foo}")
    end

    it "collapses resource patterns and constrained placeholders" do
      # Google AIP / gRPC transcoding — the pattern is a constraint on `name`,
      # and left in place the `*` pass nested braces inside the placeholder.
      helper.test_normalize_oas_path("/v1/{name=projects/*/locations/*}/res")
        .should eq("/v1/{name}/res")
      # Play routes spell a constrained param `$path<.+>`.
      helper.test_normalize_oas_path("/files/$path<.+>").should eq("/files/{path}")
    end

    it "collapses catch-all placeholders that keep the star inside the braces" do
      # Armeria writes the rest-of-path capture as `{*filePath}`, Salvo as
      # `{**path}`, ASP.NET and Spring as `{*slug}`. The `*` passes used to run
      # inside the existing placeholder and emit the nested, unbalanced
      # `{{filePath}}` / `{{wildcard}{path}}` — not path templates at all, and
      # their declared `filePath` / `path` parameters bound to nothing.
      helper.test_normalize_oas_path("/annotated/files/{*filePath}")
        .should eq("/annotated/files/{filePath}")
      helper.test_normalize_oas_path("/assets/{**path}").should eq("/assets/{path}")
      # A bare `*` segment still becomes a named variable.
      helper.test_normalize_oas_path("/files/*").should eq("/files/{wildcard}")
    end
  end

  describe "#extract_unmapped_path_parameters" do
    it "drops path parameters with no matching template expression" do
      parameters = [
        {"name" => JSON::Any.new("id"), "in" => JSON::Any.new("path")},
        {"name" => JSON::Any.new("q"), "in" => JSON::Any.new("query")},
        {"name" => JSON::Any.new("ghost"), "in" => JSON::Any.new("path")},
      ]

      helper.test_extract_unmapped_path_parameters(parameters, ["id"]).should eq(["ghost"])
      parameters.map(&.["name"].as_s).should eq(["id", "q"])
    end
  end

  describe "#path_template_names" do
    it "extracts path template parameter names" do
      helper.test_path_template_names("/users/{id}/posts/{post_id}").should eq(["id", "post_id"])
    end
  end

  describe "#operation_methods" do
    it "returns valid operation methods" do
      helper.test_operation_methods("GET").should eq(["get"])
      helper.test_operation_methods("POST").should eq(["post"])
    end

    it "expands ANY/ALL methods into all valid HTTP methods" do
      methods = helper.test_operation_methods("ANY")
      methods.should contain("get")
      methods.should contain("post")
      methods.should contain("delete")
    end

    it "returns empty array for unrecognized methods" do
      helper.test_operation_methods("INVALID").should be_empty
    end
  end

  describe "#swagger_url_parts" do
    it "parses url parts properly" do
      parts = helper.test_swagger_url_parts("https://api.example.com/v1")
      parts[:host].should eq("api.example.com")
      parts[:base_path].should eq("/v1")
      parts[:schemes].should eq(["https"])
    end

    it "handles scheme-less urls" do
      parts = helper.test_swagger_url_parts("api.example.com/v1")
      parts[:host].should eq("api.example.com")
      parts[:base_path].should eq("/v1")
      parts[:schemes].should eq(["http", "https"])
    end
  end
end
