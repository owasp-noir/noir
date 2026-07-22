require "../../spec_helper"
require "../../../src/output_builder/oas_common"

private struct OasCommonTestHelper
  include OutputBuilderOasCommon

  def test_normalize_oas_path(raw_url : String)
    normalize_oas_path(raw_url)
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
