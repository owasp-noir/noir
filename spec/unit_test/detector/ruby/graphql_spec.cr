require "../../../spec_helper"
require "../../../../src/detector/detectors/ruby/*"

describe "Detect Ruby GraphQL (graphql-ruby)" do
  options = create_test_options
  instance = Detector::Ruby::Graphql.new options

  it "detects a GraphQL::Schema subclass" do
    instance.detect("app/graphql/app_schema.rb", "class AppSchema < GraphQL::Schema\n  query Types::QueryType\nend").should be_true
  end

  it "detects a GraphQL::Schema::Object subclass" do
    instance.detect("app/graphql/types/base_object.rb", "module Types\n  class BaseObject < ::GraphQL::Schema::Object\n  end\nend").should be_true
  end

  it "ignores graphql-client usage" do
    client = <<-RB
      require "graphql/client"
      Schema = GraphQL::Client.load_schema(HTTP)
      Client = GraphQL::Client.new(schema: Schema, execute: HTTP)
      RB
    instance.detect("lib/github.rb", client).should be_false
  end

  it "ignores non-Ruby files" do
    instance.detect("schema.py", "class AppSchema < GraphQL::Schema").should be_false
  end
end
