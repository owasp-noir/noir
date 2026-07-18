require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/directus"

private def analyze_directus(content : String)
  path = File.tempname("snapshot", ".yaml")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "directus-snapshot"
  locator.push "directus-snapshot", path

  options = create_test_options
  analyzer = Analyzer::Specification::Directus.new options
  analyzer.analyze
ensure
  locator = CodeLocator.instance
  locator.clear "directus-snapshot"
  File.delete(path) if path && File.exists?(path)
end

describe "Directus Analyzer" do
  it "expands a collection into the items CRUD family" do
    endpoints = analyze_directus <<-YAML
      directus: 10.13.0
      collections:
        - collection: posts
          meta:
            singleton: false
          schema:
            name: posts
      fields: []
      YAML

    pairs = endpoints.map { |e| {e.method, e.url} }
    pairs.should contain({"GET", "/items/posts"})
    pairs.should contain({"POST", "/items/posts"})
    pairs.should contain({"PATCH", "/items/posts"})
    pairs.should contain({"DELETE", "/items/posts"})
    pairs.should contain({"GET", "/items/posts/{id}"})
    pairs.should contain({"PATCH", "/items/posts/{id}"})
    pairs.should contain({"DELETE", "/items/posts/{id}"})
    endpoints.size.should eq(7)
  end

  it "emits a singleton at /singleton with no listing or id segment" do
    endpoints = analyze_directus <<-YAML
      directus: 10.13.0
      collections:
        - collection: site_settings
          meta:
            singleton: true
          schema:
            name: site_settings
      fields:
        - collection: site_settings
          field: site_name
          type: string
      YAML

    endpoints.size.should eq(2)
    endpoints.map(&.url).uniq!.should eq(["/items/site_settings/singleton"])
    endpoints.map(&.method).sort!.should eq(["GET", "PATCH"])
    endpoints.find! { |e| e.method == "PATCH" }
      .params.any? { |p| p.name == "site_name" && p.param_type == "json" }.should be_true
  end

  it "skips directus_* system collections" do
    endpoints = analyze_directus <<-YAML
      directus: 10.13.0
      collections:
        - collection: directus_users
          schema:
            name: directus_users
        - collection: directus_files
          schema:
            name: directus_files
      fields: []
      YAML

    endpoints.size.should eq(0)
  end

  # A collection with a null schema is a UI folder - it has no table and
  # therefore no /items route.
  it "skips folder collections with a null schema" do
    endpoints = analyze_directus <<-YAML
      directus: 10.13.0
      collections:
        - collection: content
          meta:
            singleton: false
          schema: null
      fields: []
      YAML

    endpoints.size.should eq(0)
  end

  it "omits auto-increment keys and relational aliases from body params" do
    endpoints = analyze_directus <<-YAML
      directus: 10.13.0
      collections:
        - collection: posts
          schema:
            name: posts
      fields:
        - collection: posts
          field: id
          type: integer
          meta:
            readonly: true
          schema:
            has_auto_increment: true
        - collection: posts
          field: title
          type: string
        - collection: posts
          field: comments
          type: alias
          meta:
            special:
              - o2m
      YAML

    create = endpoints.find! { |e| e.method == "POST" && e.url == "/items/posts" }
    names = create.params.map(&.name)
    names.should contain("title")
    names.should_not contain("id")
    names.should_not contain("comments")
  end

  # Readonly fields cannot be written but are entirely filterable, so
  # they belong in the query vocabulary even though they are not body
  # params.
  it "keeps readonly fields filterable while excluding aliases" do
    endpoints = analyze_directus <<-YAML
      directus: 10.13.0
      collections:
        - collection: posts
          schema:
            name: posts
      fields:
        - collection: posts
          field: id
          type: integer
          meta:
            readonly: true
          schema:
            has_auto_increment: true
        - collection: posts
          field: comments
          type: alias
          meta:
            special:
              - o2m
      YAML

    list = endpoints.find! { |e| e.method == "GET" && e.url == "/items/posts" }
    query_names = list.params.select { |p| p.param_type == "query" }.map(&.name)
    query_names.should contain("filter[id][_eq]")
    query_names.should_not contain("filter[comments][_eq]")
    # The global vocabulary is always available.
    query_names.should contain("filter")
    query_names.should contain("limit")
  end

  it "nests body params under data on the batch update endpoint" do
    endpoints = analyze_directus <<-YAML
      directus: 10.13.0
      collections:
        - collection: posts
          schema:
            name: posts
      fields:
        - collection: posts
          field: title
          type: string
      YAML

    batch = endpoints.find! { |e| e.method == "PATCH" && e.url == "/items/posts" }
    names = batch.params.map(&.name)
    names.should contain("keys")
    names.should contain("data.title")

    item = endpoints.find! { |e| e.method == "PATCH" && e.url == "/items/posts/{id}" }
    item.params.map(&.name).should contain("title")
  end

  it "maps field types to value hints" do
    endpoints = analyze_directus <<-YAML
      directus: 10.13.0
      collections:
        - collection: posts
          schema:
            name: posts
      fields:
        - collection: posts
          field: title
          type: string
        - collection: posts
          field: views
          type: integer
        - collection: posts
          field: ratio
          type: float
        - collection: posts
          field: created
          type: timestamp
        - collection: posts
          field: payload
          type: json
      YAML

    create = endpoints.find! { |e| e.method == "POST" }
    create.params.find! { |p| p.name == "title" }.value.should eq("string")
    create.params.find! { |p| p.name == "views" }.value.should eq("int")
    create.params.find! { |p| p.name == "ratio" }.value.should eq("number")
    create.params.find! { |p| p.name == "created" }.value.should eq("datetime")
    create.params.find! { |p| p.name == "payload" }.value.should eq("object")
  end
end
