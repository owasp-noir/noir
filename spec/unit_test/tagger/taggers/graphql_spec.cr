require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/graphql.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "GraphqlTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = GraphqlTagger.new(default_tagger_options)
      tagger.should_not be_nil
    end
  end

  describe "perform" do
    it "tags endpoint with query and mutation parameters" do
      tagger = GraphqlTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api", "POST", [
        Param.new("query", "{ users { id } }", "form"),
        Param.new("operationName", "GetUsers", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("graphql")
    end

    it "tags endpoint with GraphQL URL path" do
      tagger = GraphqlTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/graphql", "POST", [
        Param.new("query", "{ users { id } }", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("graphql")
    end

    it "tags endpoint with /gql URL path" do
      tagger = GraphqlTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/gql", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("graphql")
    end

    it "does not tag endpoint without GraphQL parameters" do
      tagger = GraphqlTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/users", "GET", [
        Param.new("user_id", "123", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "tags endpoint with schema introspection parameter" do
      tagger = GraphqlTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api", "POST", [
        Param.new("query", "", "form"),
        Param.new("__schema", "", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("graphql")
    end

    it "handles multiple endpoints" do
      tagger = GraphqlTagger.new(default_tagger_options)

      endpoint1 = Endpoint.new("/graphql", "POST", [
        Param.new("query", "{ users { id } }", "form"),
      ])

      endpoint2 = Endpoint.new("/api/users", "GET", [
        Param.new("name", "John", "query"),
      ])

      tagger.perform([endpoint1, endpoint2])

      endpoint1.tags.size.should eq(1)
      endpoint2.tags.size.should eq(0)
    end

    it "is case-insensitive for parameter matching" do
      tagger = GraphqlTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api", "POST", [
        Param.new("Query", "{ users { id } }", "form"),
        Param.new("Mutation", "createUser", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
    end
  end
end
