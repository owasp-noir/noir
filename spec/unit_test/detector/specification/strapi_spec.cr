require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Strapi" do
  options = create_test_options
  instance = Detector::Specification::Strapi.new options

  schema = <<-JSON
    {
      "kind": "collectionType",
      "collectionName": "articles",
      "info": { "singularName": "article", "pluralName": "articles" },
      "attributes": { "title": { "type": "string" } }
    }
    JSON

  routes = <<-TS
    export default {
      routes: [
        { method: 'GET', path: '/articles/featured', handler: 'article.featured' },
      ],
    };
    TS

  it "detects a content-type schema.json" do
    instance.detect("src/api/article/content-types/article/schema.json", schema).should be_true
  end

  it "detects a singleType schema" do
    content = <<-JSON
      {
        "kind": "singleType",
        "info": { "singularName": "homepage", "pluralName": "homepages" },
        "attributes": {}
      }
      JSON

    instance.detect("src/api/homepage/content-types/homepage/schema.json", content).should be_true
  end

  it "detects a plugin content-type schema" do
    instance.detect("src/plugins/blog/server/content-types/post/schema.json", schema).should be_true
  end

  # schema.json is one of the most common filenames there is. The
  # /content-types/ segment plus the Strapi-only kind literal is what
  # narrows it.
  it "ignores a JSON Schema document named schema.json" do
    content = <<-JSON
      {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "type": "object",
        "properties": { "title": { "type": "string" } }
      }
      JSON

    instance.detect("src/api/article/content-types/article/schema.json", content).should be_false
  end

  it "ignores a content-type schema with an unknown kind" do
    content = <<-JSON
      {
        "kind": "somethingElse",
        "info": { "singularName": "a", "pluralName": "b" },
        "attributes": {}
      }
      JSON

    instance.detect("src/api/a/content-types/a/schema.json", content).should be_false
  end

  it "ignores a Strapi-shaped schema outside a content-types directory" do
    instance.detect("config/schema.json", schema).should be_false
    instance.detect("src/api/article/schema.json", schema).should be_false
  end

  it "detects a routes module under src/api" do
    instance.detect("src/api/article/routes/custom-article.ts", routes).should be_true
  end

  it "detects a createCoreRouter module" do
    content = <<-TS
      import { factories } from '@strapi/strapi';
      export default factories.createCoreRouter('api::article.article');
      TS

    instance.detect("src/api/article/routes/article.ts", content).should be_true
  end

  it "detects a plugin routes module under server/" do
    instance.detect("src/plugins/blog/server/routes/index.js", routes).should be_true
  end

  # SvelteKit's src/routes/api/... contains both path segments in the
  # opposite order. Only the ordering distinguishes it from Strapi.
  it "ignores a SvelteKit route module" do
    content = <<-TS
      export const GET = async ({ url }) => {
        return new Response('ok');
      };
      TS

    instance.detect("src/routes/api/articles/+server.ts", content).should be_false
    # Even carrying a Strapi-shaped array, the path ordering rejects it.
    instance.detect("src/routes/api/articles/+server.ts", routes).should be_false
  end

  # This exact shape lives at spec/functional_test/fixtures/javascript/koa/
  # routes/strapi_style.js as a Koa regression guard. It must not be
  # claimed as Strapi.
  it "ignores a Strapi-style routes array outside src/api" do
    content = <<-JS
      module.exports = (strapi) => {
        return [
          { method: 'GET', path: '/strapi/items', handler: 'item.find' },
        ];
      };
      JS

    instance.detect("routes/strapi_style.js", content).should be_false
  end

  it "ignores a routes module with no handler key" do
    content = <<-TS
      export default {
        routes: [
          { method: 'GET', path: '/articles' },
        ],
      };
      TS

    instance.detect("src/api/article/routes/custom.ts", content).should be_false
  end

  it "registers schema and route paths under separate locator keys" do
    locator = CodeLocator.instance
    locator.clear "strapi-schema"
    locator.clear "strapi-routes"

    instance.detect("src/api/article/content-types/article/schema.json", schema)
    instance.detect("src/api/article/routes/custom-article.ts", routes)

    locator.all("strapi-schema").should eq(["src/api/article/content-types/article/schema.json"])
    locator.all("strapi-routes").should eq(["src/api/article/routes/custom-article.ts"])
  end
end
