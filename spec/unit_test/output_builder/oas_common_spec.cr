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

  def test_document_server_url(raw_url : String)
    document_server_url(raw_url)
  end

  def test_path_template_shape(path : String)
    path_template_shape(path)
  end

  def test_path_template_renames(from : String, to : String)
    path_template_renames(from, to)
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
      parts[:schemes].should eq(["https"])
    end

    it "handles scheme-less urls" do
      parts = helper.test_swagger_url_parts("api.example.com/v1")
      parts[:host].should eq("api.example.com")
      parts[:schemes].should eq(["http", "https"])
    end

    it "keeps an explicit port in the Swagger host" do
      # Swagger 2.0's `host` is `host[:port]`; dropping the port aimed every
      # generated client at 443/80 instead of the port `-u` named.
      helper.test_swagger_url_parts("https://api.example.com:8443/v2")[:host]
        .should eq("api.example.com:8443")
      helper.test_swagger_url_parts("api.example.com:8080")[:host]
        .should eq("api.example.com:8080")
    end

    it "leaves a default port off the Swagger host" do
      helper.test_swagger_url_parts("https://api.example.com/")[:host]
        .should eq("api.example.com")
      helper.test_swagger_url_parts("https://api.example.com:443/v2")[:host]
        .should eq("api.example.com")
      helper.test_swagger_url_parts("http://api.example.com:80/v2")[:host]
        .should eq("api.example.com")
    end

    it "reports no host when the url names none" do
      helper.test_swagger_url_parts("")[:host].should be_nil
      helper.test_swagger_url_parts("")[:schemes].should eq(["http", "https"])
    end
  end

  describe "#document_server_url" do
    it "drops the base path the optimizer already prefixed onto every route" do
      helper.test_document_server_url("https://api.example.com/v2")
        .should eq("https://api.example.com")
      helper.test_document_server_url("https://api.example.com:8443/v2")
        .should eq("https://api.example.com:8443")
      helper.test_document_server_url("https://api.example.com")
        .should eq("https://api.example.com")
      helper.test_document_server_url("").should eq("http://localhost")
    end

    it "falls back to a bare root when the url names no authority" do
      helper.test_document_server_url("/api").should eq("/")
    end
  end

  describe "#path_template_shape" do
    it "erases template variable names" do
      # OAS 2.0 and 3.x both treat two templated paths with the same
      # hierarchy but different variable names as one path.
      helper.test_path_template_shape("/users/{id}").should eq("/users/{}")
      helper.test_path_template_shape("/users/{userId}").should eq("/users/{}")
      helper.test_path_template_shape("/users/{id}/posts/{postId}")
        .should eq("/users/{}/posts/{}")
      helper.test_path_template_shape("/users/id").should eq("/users/id")
    end
  end

  describe "#path_template_renames" do
    it "maps variable names slot by slot" do
      helper.test_path_template_renames("/users/{userId}", "/users/{id}")
        .should eq({"userId" => "id"})
      helper.test_path_template_renames("/a/{x}/b/{y}", "/a/{p}/b/{q}")
        .should eq({"x" => "p", "y" => "q"})
    end

    it "reports nothing for names that already agree" do
      helper.test_path_template_renames("/a/{x}/b/{y}", "/a/{x}/b/{q}")
        .should eq({"y" => "q"})
    end
  end
end
