require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/hasura"

private def analyze_hasura(tables : String? = nil, rest : String? = nil)
  paths = [] of String
  locator = CodeLocator.instance
  locator.clear "hasura-tables"
  locator.clear "hasura-rest-endpoints"

  if tables
    path = File.tempname("hasura_tables", ".yaml")
    File.write(path, tables)
    paths << path
    locator.push "hasura-tables", path
  end

  if rest
    path = File.tempname("hasura_rest", ".yaml")
    File.write(path, rest)
    paths << path
    locator.push "hasura-rest-endpoints", path
  end

  options = create_test_options
  Analyzer::Specification::Hasura.new(options).analyze
ensure
  locator = CodeLocator.instance
  locator.clear "hasura-tables"
  locator.clear "hasura-rest-endpoints"
  paths.try &.each { |p| File.delete(p) if File.exists?(p) }
end

describe "Hasura Analyzer" do
  # A tracked table produces GraphQL root fields, never per-table REST.
  it "emits GraphQL root fields on /v1/graphql with fragment URLs" do
    endpoints = analyze_hasura(tables: <<-YAML)
      table:
        name: movies
        schema: public
      select_permissions:
        - role: public
          permission:
            columns:
              - id
              - title
            filter: {}
      YAML

    urls = endpoints.map(&.url)
    urls.should contain("/v1/graphql#Query.movies")
    urls.should contain("/v1/graphql#Query.movies_aggregate")
    urls.should contain("/v1/graphql#Mutation.insert_movies")
    urls.should contain("/v1/graphql#Mutation.insert_movies_one")
    urls.should contain("/v1/graphql#Mutation.update_movies")
    urls.should contain("/v1/graphql#Mutation.delete_movies")
    endpoints.map(&.method).uniq!.should eq(["POST"])
    # Per-table REST routes do not exist in Hasura and must not appear.
    endpoints.none?(&.url.starts_with?("/api/rest/movies")).should be_true
  end

  # The primary key is not recorded in metadata, so a by_pk field is only
  # emitted when an `id` column is actually named.
  it "emits by_pk fields only when an id column is present" do
    with_id = analyze_hasura(tables: <<-YAML)
      table:
        name: movies
        schema: public
      select_permissions:
        - role: public
          permission:
            columns:
              - id
            filter: {}
      YAML

    with_id.map(&.url).should contain("/v1/graphql#Query.movies_by_pk")

    without_id = analyze_hasura(tables: <<-YAML)
      table:
        name: directors
        schema: public
      select_permissions:
        - role: public
          permission:
            columns:
              - name
            filter: {}
      YAML

    without_id.none?(&.url.includes?("_by_pk")).should be_true
  end

  it "unions columns across permission blocks into input params" do
    endpoints = analyze_hasura(tables: <<-YAML)
      table:
        name: movies
        schema: public
      select_permissions:
        - role: public
          permission:
            columns:
              - id
              - title
            filter: {}
      insert_permissions:
        - role: user
          permission:
            check: {}
            columns:
              - title
              - release_year
      YAML

    insert = endpoints.find! { |e| e.url == "/v1/graphql#Mutation.insert_movies_one" }
    names = insert.params.map(&.name)
    names.any?(&.includes?("title")).should be_true
    names.any?(&.includes?("release_year")).should be_true
  end

  it "provides a replayable operation document per field" do
    endpoints = analyze_hasura(tables: <<-YAML)
      table:
        name: movies
        schema: public
      select_permissions:
        - role: public
          permission:
            columns:
              - id
            filter: {}
      YAML

    query = endpoints.find! { |e| e.url == "/v1/graphql#Query.movies" }
    doc = query.params.find! { |p| p.name == "graphql_query_movies" }
    doc.param_type.should eq("json")
    doc.value.should contain("query")
    doc.value.should contain("movies")
  end

  it "prefixes root fields for non-public schemas" do
    endpoints = analyze_hasura(tables: <<-YAML)
      table:
        name: orders
        schema: storefront
      select_permissions:
        - role: public
          permission:
            columns:
              - id
            filter: {}
      YAML

    endpoints.map(&.url).should contain("/v1/graphql#Query.storefront_orders")
  end

  it "reads the legacy flat array form" do
    endpoints = analyze_hasura(tables: <<-YAML)
      - table:
          name: movies
          schema: public
        select_permissions:
          - role: public
            permission:
              columns:
                - id
              filter: {}
      - table:
          name: directors
          schema: public
      YAML

    urls = endpoints.map(&.url)
    urls.should contain("/v1/graphql#Query.movies")
    urls.should contain("/v1/graphql#Query.directors")
  end

  # CLI v3 writes tables.yaml as a list of include strings.
  it "skips an include-only tables.yaml" do
    endpoints = analyze_hasura(tables: <<-YAML)
      - "!include public_movies.yaml"
      - "!include public_directors.yaml"
      YAML

    endpoints.size.should eq(0)
  end

  it "still emits root fields for an admin-only table with no permissions" do
    endpoints = analyze_hasura(tables: <<-YAML)
      table:
        name: audit
        schema: public
      YAML

    endpoints.map(&.url).should contain("/v1/graphql#Query.audit")
  end

  it "emits declared REST endpoints under /api/rest" do
    endpoints = analyze_hasura(rest: <<-YAML)
      - name: getMovie
        url: movie/:id
        methods:
          - GET
      - name: upsertMovie
        url: movie
        methods:
          - POST
          - PUT
      YAML

    pairs = endpoints.map { |e| {e.method, e.url} }
    pairs.should contain({"GET", "/api/rest/movie/{id}"})
    pairs.should contain({"POST", "/api/rest/movie"})
    pairs.should contain({"PUT", "/api/rest/movie"})
  end

  it "tags GraphQL endpoints with their source table" do
    endpoints = analyze_hasura(tables: <<-YAML)
      table:
        name: movies
        schema: public
      YAML

    endpoints.first.tags.any? { |t| t.name == "hasura" && t.description == "table:public.movies" }.should be_true
  end
end
