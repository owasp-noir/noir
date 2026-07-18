require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/payload_cms"

private def analyze_payload(collection : String? = nil, global : String? = nil, config : String? = nil)
  paths = [] of String
  locator = CodeLocator.instance
  locator.clear "payload-collection"
  locator.clear "payload-global"
  locator.clear "payload-config"

  if collection
    path = File.tempname("payload_collection", ".ts")
    File.write(path, collection)
    paths << path
    locator.push "payload-collection", path
  end

  if global
    path = File.tempname("payload_global", ".ts")
    File.write(path, global)
    paths << path
    locator.push "payload-global", path
  end

  if config
    path = File.tempname("payload_config", ".ts")
    File.write(path, config)
    paths << path
    locator.push "payload-config", path
  end

  options = create_test_options
  Analyzer::Specification::PayloadCms.new(options).analyze
ensure
  locator = CodeLocator.instance
  locator.clear "payload-collection"
  locator.clear "payload-global"
  locator.clear "payload-config"
  paths.try &.each { |p| File.delete(p) if File.exists?(p) }
end

describe "Payload CMS Analyzer" do
  it "expands a collection into its CRUD family" do
    endpoints = analyze_payload(collection: <<-TS)
      import type { CollectionConfig } from 'payload'
      export const Posts: CollectionConfig = {
        slug: 'posts',
        fields: [{ name: 'title', type: 'text' }],
      }
      TS

    pairs = endpoints.map { |e| {e.method, e.url} }
    pairs.should contain({"GET", "/api/posts"})
    pairs.should contain({"POST", "/api/posts"})
    pairs.should contain({"PATCH", "/api/posts"})
    pairs.should contain({"DELETE", "/api/posts"})
    pairs.should contain({"GET", "/api/posts/count"})
    pairs.should contain({"GET", "/api/posts/{id}"})
    pairs.should contain({"PATCH", "/api/posts/{id}"})
    pairs.should contain({"DELETE", "/api/posts/{id}"})
    endpoints.size.should eq(8)
  end

  # Layout wrappers carry no name, so their children live at the parent
  # level in the stored document. Most real configs use them.
  it "hoists fields out of row, collapsible and ui wrappers" do
    endpoints = analyze_payload(collection: <<-TS)
      import type { CollectionConfig } from 'payload'
      export const Posts: CollectionConfig = {
        slug: 'posts',
        fields: [
          { name: 'title', type: 'text' },
          {
            type: 'row',
            fields: [
              { name: 'views', type: 'number' },
              {
                type: 'collapsible',
                fields: [{ name: 'featured', type: 'checkbox' }],
              },
            ],
          },
        ],
      }
      TS

    names = endpoints.find! { |e| e.method == "POST" }.params.map(&.name)
    names.should contain("title")
    names.should contain("views")
    names.should contain("featured")
    # The wrapper itself is not a field.
    names.should_not contain("row")
    names.should_not contain("row.views")
  end

  it "nests group and array children under their parent name" do
    endpoints = analyze_payload(collection: <<-TS)
      import type { CollectionConfig } from 'payload'
      export const Posts: CollectionConfig = {
        slug: 'posts',
        fields: [
          {
            name: 'meta',
            type: 'group',
            fields: [{ name: 'description', type: 'textarea' }],
          },
          {
            name: 'gallery',
            type: 'array',
            fields: [{ name: 'caption', type: 'text' }],
          },
        ],
      }
      TS

    names = endpoints.find! { |e| e.method == "POST" }.params.map(&.name)
    names.should contain("meta")
    names.should contain("meta.description")
    names.should contain("gallery")
    names.should contain("gallery.caption")
  end

  it "nests named tabs but hoists unnamed ones" do
    endpoints = analyze_payload(collection: <<-TS)
      import type { CollectionConfig } from 'payload'
      export const Posts: CollectionConfig = {
        slug: 'posts',
        fields: [
          {
            type: 'tabs',
            tabs: [
              { label: 'Content', fields: [{ name: 'body', type: 'textarea' }] },
              { name: 'seo', label: 'SEO', fields: [{ name: 'metaTitle', type: 'text' }] },
            ],
          },
        ],
      }
      TS

    names = endpoints.find! { |e| e.method == "POST" }.params.map(&.name)
    names.should contain("body")
    names.should contain("seo.metaTitle")
    names.should_not contain("metaTitle")
  end

  it "emits the auth route family only when auth is enabled" do
    with_auth = analyze_payload(collection: <<-TS)
      import type { CollectionConfig } from 'payload'
      export const Users: CollectionConfig = {
        slug: 'users',
        auth: true,
        fields: [{ name: 'name', type: 'text' }],
      }
      TS

    urls = with_auth.map(&.url)
    urls.should contain("/api/users/login")
    urls.should contain("/api/users/me")
    urls.should contain("/api/users/reset-password")
    login = with_auth.find! { |e| e.url == "/api/users/login" }
    login.params.map(&.name).should contain("password")

    without_auth = analyze_payload(collection: <<-TS)
      import type { CollectionConfig } from 'payload'
      export const Posts: CollectionConfig = {
        slug: 'posts',
        fields: [{ name: 'title', type: 'text' }],
      }
      TS

    without_auth.none?(&.url.includes?("/login")).should be_true
  end

  it "emits version routes only when versions are enabled" do
    endpoints = analyze_payload(collection: <<-TS)
      import type { CollectionConfig } from 'payload'
      export const Posts: CollectionConfig = {
        slug: 'posts',
        versions: { drafts: true },
        fields: [{ name: 'title', type: 'text' }],
      }
      TS

    urls = endpoints.map(&.url)
    urls.should contain("/api/posts/versions")
    urls.should contain("/api/posts/versions/{id}")
  end

  it "mounts custom endpoints under the collection and normalizes colon params" do
    endpoints = analyze_payload(collection: <<-TS)
      import type { CollectionConfig } from 'payload'
      export const Posts: CollectionConfig = {
        slug: 'posts',
        fields: [{ name: 'title', type: 'text' }],
        endpoints: [
          { path: '/:id/tracking', method: 'get', handler: async () => {} },
          { path: '/bulk-publish', method: 'post', handler: async () => {} },
        ],
      }
      TS

    pairs = endpoints.map { |e| {e.method, e.url} }
    pairs.should contain({"GET", "/api/posts/{id}/tracking"})
    pairs.should contain({"POST", "/api/posts/bulk-publish"})
  end

  it "serves globals at /api/globals and updates them with POST" do
    endpoints = analyze_payload(global: <<-TS)
      import type { GlobalConfig } from 'payload'
      export const Settings: GlobalConfig = {
        slug: 'site-settings',
        fields: [{ name: 'siteName', type: 'text' }],
      }
      TS

    endpoints.size.should eq(2)
    endpoints.map(&.url).uniq!.should eq(["/api/globals/site-settings"])
    endpoints.map(&.method).sort!.should eq(["GET", "POST"])
  end

  # buildConfig({ routes: { api: '/custom' } }) relocates the whole
  # REST mount.
  it "honours a custom api route from buildConfig" do
    endpoints = analyze_payload(
      collection: <<-TS,
        import type { CollectionConfig } from 'payload'
        export const Posts: CollectionConfig = {
          slug: 'posts',
          fields: [{ name: 'title', type: 'text' }],
        }
        TS
      config: <<-TS
        import { buildConfig } from 'payload'
        export default buildConfig({
          routes: { api: '/custom-api' },
          collections: [],
        })
        TS
    )

    endpoints.map(&.url).should contain("/custom-api/posts")
    endpoints.none?(&.url.starts_with?("/api/")).should be_true
  end

  it "emits the Payload query vocabulary rather than bare field names" do
    endpoints = analyze_payload(collection: <<-TS)
      import type { CollectionConfig } from 'payload'
      export const Posts: CollectionConfig = {
        slug: 'posts',
        fields: [{ name: 'title', type: 'text' }],
      }
      TS

    list = endpoints.find! { |e| e.method == "GET" && e.url == "/api/posts" }
    names = list.params.select { |p| p.param_type == "query" }.map(&.name)
    names.should contain("depth")
    names.should contain("draft")
    names.should contain("where[title][equals]")
    names.should_not contain("title")
  end

  it "reads several collections declared in one file" do
    endpoints = analyze_payload(collection: <<-TS)
      import type { CollectionConfig } from 'payload'

      export const Posts: CollectionConfig = {
        slug: 'posts',
        fields: [{ name: 'title', type: 'text' }],
      }

      export const Tags: CollectionConfig = {
        slug: 'tags',
        fields: [{ name: 'label', type: 'text' }],
      }
      TS

    urls = endpoints.map(&.url).uniq!
    urls.should contain("/api/posts")
    urls.should contain("/api/tags")
  end
end
