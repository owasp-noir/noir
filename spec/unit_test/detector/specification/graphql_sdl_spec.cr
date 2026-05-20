require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect GraphQL SDL" do
  options = create_test_options
  instance = Detector::Specification::GraphqlSdl.new options

  it ".graphql with type Query" do
    content = <<-SDL
      type Query {
        hello: String
      }
      SDL

    instance.detect("schema.graphql", content).should be_true
  end

  it ".graphqls with schema block" do
    content = <<-SDL
      schema {
        query: Root
      }
      type Root {
        ok: Boolean
      }
      SDL

    instance.detect("schema.graphqls", content).should be_true
  end

  it ".gql with extend type" do
    content = <<-SDL
      extend type Query {
        ping: String
      }
      SDL

    instance.detect("schema.gql", content).should be_true
  end

  it "rejects operation documents (no SDL signals)" do
    content = <<-SDL
      query GetUser { user(id: "1") { id } }
      mutation Update { updateUser(name: "x") { id } }
      SDL

    instance.detect("ops.graphql", content).should be_false
  end

  it "rejects non-graphql files" do
    instance.applicable?("schema.json").should be_false
  end

  it "registers path in code_locator" do
    content = "type Query { ok: Boolean }"
    locator = CodeLocator.instance
    locator.clear "graphql-sdl"
    instance.detect("schema.graphql", content)
    locator.all("graphql-sdl").should eq(["schema.graphql"])
  end
end
