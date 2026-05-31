require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/api_docs.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "ApiDocsTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = ApiDocsTagger.new(default_tagger_options)
      tagger.name.should eq("api_docs")
    end
  end

  describe "perform" do
    it "tags a Swagger UI endpoint" do
      tagger = ApiDocsTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/swagger-ui.html", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("api_docs")
    end

    it "tags a Spring /v3/api-docs endpoint" do
      tagger = ApiDocsTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/v3/api-docs", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("api_docs")
    end

    it "tags an openapi.json spec endpoint" do
      tagger = ApiDocsTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/openapi.json", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("api_docs")
    end

    it "tags a GraphiQL explorer endpoint" do
      tagger = ApiDocsTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/graphiql", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("api_docs")
    end

    it "tags a drf-spectacular /api/schema endpoint" do
      tagger = ApiDocsTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/schema/", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("api_docs")
    end

    it "does not tag a bare schema segment without api/openapi context" do
      tagger = ApiDocsTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/graphql/schema", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag a generic /docs documentation path" do
      tagger = ApiDocsTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/docs/getting-started", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag a benign endpoint" do
      tagger = ApiDocsTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/products", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end
  end
end
