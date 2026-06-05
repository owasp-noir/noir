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

  it "detects SDL with regular-string description on same line as declaration" do
    content = <<-SDL
      "Description for the root" type Query {
        hello: String
      }
      SDL

    instance.detect("schema.graphql", content).should be_true
  end

  it "detects SDL with block-string description immediately followed by declaration on same line" do
    content = <<-SDL
      """Block desc""" type Query { hello: String }
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

  it "rejects operation documents with SDL keyword field names" do
    content = <<-GQL
      query GetStore {
        store {
          id
          type
          schema {
            enum
          }
        }
      }
      GQL

    instance.detect("ops.graphql", content).should be_false
  end

  it "rejects operation documents even when string literals contain braces, #, or SDL keywords" do
    # Strings can contain example SDL, # (not comments), or unbalanced braces.
    # These must not affect depth tracking or cause false SDL detection.
    content = <<-GQL
      query GetStore($filter: Filter = "{ schema: 1 } # not a comment", $desc: String = "type Query { x }") {
        store {
          id
          type
          schema {
            enum
          }
        }
      }
      GQL

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
