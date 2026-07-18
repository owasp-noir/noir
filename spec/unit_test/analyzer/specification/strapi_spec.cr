require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/strapi"

private def analyze_strapi_schema(content : String, name = "article")
  dir = File.tempname("strapi")
  path = File.join(dir, "src", "api", name, "content-types", name)
  Dir.mkdir_p(path)
  file = File.join(path, "schema.json")
  File.write(file, content)

  locator = CodeLocator.instance
  locator.clear "strapi-schema"
  locator.clear "strapi-routes"
  locator.push "strapi-schema", file

  options = create_test_options
  Analyzer::Specification::Strapi.new(options).analyze
ensure
  locator = CodeLocator.instance
  locator.clear "strapi-schema"
  locator.clear "strapi-routes"
  FileUtils.rm_rf(dir) if dir && Dir.exists?(dir)
end

private def analyze_strapi_routes(content : String)
  path = File.tempname("strapi_routes", ".ts")
  File.write(path, content)

  locator = CodeLocator.instance
  locator.clear "strapi-schema"
  locator.clear "strapi-routes"
  locator.push "strapi-routes", path

  options = create_test_options
  Analyzer::Specification::Strapi.new(options).analyze
ensure
  locator = CodeLocator.instance
  locator.clear "strapi-schema"
  locator.clear "strapi-routes"
  File.delete(path) if path && File.exists?(path)
end

describe "Strapi Analyzer" do
  it "expands a collectionType into five verbs on the plural name" do
    endpoints = analyze_strapi_schema <<-JSON
      {
        "kind": "collectionType",
        "info": { "singularName": "article", "pluralName": "articles" },
        "attributes": {}
      }
      JSON

    pairs = endpoints.map { |e| {e.method, e.url} }
    pairs.should contain({"GET", "/api/articles"})
    pairs.should contain({"POST", "/api/articles"})
    pairs.should contain({"GET", "/api/articles/{documentId}"})
    # Strapi's keyed update verb is PUT, not PATCH.
    pairs.should contain({"PUT", "/api/articles/{documentId}"})
    pairs.should contain({"DELETE", "/api/articles/{documentId}"})
    endpoints.size.should eq(5)
  end

  it "expands a singleType into three verbs on the singular name" do
    endpoints = analyze_strapi_schema(<<-JSON, "homepage")
      {
        "kind": "singleType",
        "info": { "singularName": "homepage", "pluralName": "homepages" },
        "attributes": { "heading": { "type": "string" } }
      }
      JSON

    endpoints.size.should eq(3)
    endpoints.map(&.url).uniq!.should eq(["/api/homepage"])
    endpoints.map(&.method).sort!.should eq(["DELETE", "GET", "PUT"])
    # No collection listing and no id segment for a single type.
    endpoints.none?(&.url.includes?("{documentId}")).should be_true
  end

  it "wraps attributes in the data envelope and maps their types" do
    endpoints = analyze_strapi_schema <<-JSON
      {
        "kind": "collectionType",
        "info": { "singularName": "article", "pluralName": "articles" },
        "attributes": {
          "title": { "type": "string" },
          "views": { "type": "integer" },
          "featured": { "type": "boolean" },
          "publishedAt": { "type": "datetime" },
          "meta": { "type": "json" }
        }
      }
      JSON

    create = endpoints.find! { |e| e.method == "POST" }
    create.params.find! { |p| p.name == "data.title" }.value.should eq("string")
    create.params.find! { |p| p.name == "data.views" }.value.should eq("int")
    create.params.find! { |p| p.name == "data.featured" }.value.should eq("boolean")
    create.params.find! { |p| p.name == "data.publishedAt" }.value.should eq("datetime")
    create.params.find! { |p| p.name == "data.meta" }.value.should eq("object")
    # The un-enveloped name is not a wire param.
    create.params.none? { |p| p.name == "title" }.should be_true
  end

  it "omits relations, components and media from body params" do
    endpoints = analyze_strapi_schema <<-JSON
      {
        "kind": "collectionType",
        "info": { "singularName": "article", "pluralName": "articles" },
        "attributes": {
          "title": { "type": "string" },
          "author": { "type": "relation", "relation": "manyToOne", "target": "api::author.author" },
          "cover": { "type": "media" },
          "blocks": { "type": "dynamiczone", "components": [] },
          "seo": { "type": "component", "component": "shared.seo" }
        }
      }
      JSON

    names = endpoints.find! { |e| e.method == "POST" }.params.map(&.name)
    names.should contain("data.title")
    names.should_not contain("data.author")
    names.should_not contain("data.cover")
    names.should_not contain("data.blocks")
    names.should_not contain("data.seo")
  end

  it "emits the Strapi query vocabulary rather than bare attribute names" do
    endpoints = analyze_strapi_schema <<-JSON
      {
        "kind": "collectionType",
        "info": { "singularName": "article", "pluralName": "articles" },
        "attributes": { "title": { "type": "string" } }
      }
      JSON

    list = endpoints.find! { |e| e.method == "GET" && e.url == "/api/articles" }
    names = list.params.select { |p| p.param_type == "query" }.map(&.name)
    names.should contain("populate")
    names.should contain("pagination[pageSize]")
    names.should contain("filters[title][$eq]")
    names.should_not contain("title")
  end

  # A content type opted out of the content API is not served over REST.
  it "skips a content type with the content-api plugin disabled" do
    endpoints = analyze_strapi_schema <<-JSON
      {
        "kind": "collectionType",
        "info": { "singularName": "secret", "pluralName": "secrets" },
        "pluginOptions": { "content-api": { "enabled": false } },
        "attributes": {}
      }
      JSON

    endpoints.size.should eq(0)
  end

  it "falls back to collectionName when pluralName is absent" do
    endpoints = analyze_strapi_schema <<-JSON
      {
        "kind": "collectionType",
        "collectionName": "legacy_items",
        "info": { "singularName": "legacy-item" },
        "attributes": {}
      }
      JSON

    endpoints.map(&.url).should contain("/api/legacy_items")
  end

  it "notes the v4 id addressing difference on the document endpoints" do
    endpoints = analyze_strapi_schema <<-JSON
      {
        "kind": "collectionType",
        "info": { "singularName": "article", "pluralName": "articles" },
        "attributes": {}
      }
      JSON

    read = endpoints.find! { |e| e.method == "GET" && e.url.includes?("{documentId}") }
    read.tags.any? { |t| t.name == "strapi-note" }.should be_true
  end

  it "mounts custom routes under /api and normalizes colon params" do
    endpoints = analyze_strapi_routes <<-TS
      export default {
        routes: [
          { method: 'GET', path: '/articles/featured', handler: 'article.featured' },
          { method: 'POST', path: '/articles/:id/like', handler: 'article.like' },
        ],
      };
      TS

    pairs = endpoints.map { |e| {e.method, e.url} }
    pairs.should contain({"GET", "/api/articles/featured"})
    pairs.should contain({"POST", "/api/articles/{id}/like"})
    endpoints.size.should eq(2)
  end

  it "reads custom routes from a TypeScript-annotated declaration" do
    endpoints = analyze_strapi_routes <<-TS
      import type { Core } from '@strapi/strapi';

      const config: Core.RouterConfig = {
        routes: [
          { method: 'DELETE', path: '/articles/:id/archive', handler: 'article.archive' },
        ],
      };

      export default config;
      TS

    endpoints.size.should eq(1)
    endpoints.first.method.should eq("DELETE")
    endpoints.first.url.should eq("/api/articles/{id}/archive")
  end

  it "ignores a createCoreRouter module, whose routes the schema pass already emits" do
    endpoints = analyze_strapi_routes <<-TS
      import { factories } from '@strapi/strapi';
      export default factories.createCoreRouter('api::article.article');
      TS

    endpoints.size.should eq(0)
  end
end
