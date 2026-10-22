require "../../spec_helper"
require "../../../src/utils/spring_property_path"

describe SpringPropertyPath do
  it "resolves nested Spring property placeholders to their default value" do
    SpringPropertyPath.resolve("${server.error.path:${error.path:/error}}").should eq("/error")
  end

  it "uses configured property values when available" do
    properties = {"server.error.path" => "/custom-error"}
    SpringPropertyPath.resolve("${server.error.path:${error.path:/error}}", properties).should eq("/custom-error")
  end

  it "falls back through nested properties before using the final default" do
    properties = {"error.path" => "/fallback-error"}
    SpringPropertyPath.resolve("${server.error.path:${error.path:/error}}", properties).should eq("/fallback-error")
  end

  it "leaves literal paths unchanged" do
    SpringPropertyPath.resolve("/api/v1/users").should eq("/api/v1/users")
  end

  it "resolves placeholders embedded in a path" do
    SpringPropertyPath.resolve("/api/${app.version:v1}/users").should eq("/api/v1/users")
  end

  it "resolves arbitrary property keys from a properties map" do
    properties = {
      "api.base.path" => "/configured-api",
      "app.docs.path" => "/help",
    }
    SpringPropertyPath.resolve("${api.base.path:/api}/items", properties).should eq("/configured-api/items")
    SpringPropertyPath.resolve("${app.docs.path:/docs}/guide", properties).should eq("/help/guide")
  end

  it "uses inline defaults when a property is not configured" do
    SpringPropertyPath.resolve("${api.base.path:/api}/items").should eq("/api/items")
  end
end
