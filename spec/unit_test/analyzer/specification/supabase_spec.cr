require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/supabase"

private def analyze_supabase(*migrations : String, config : String? = nil)
  paths = [] of String
  locator = CodeLocator.instance
  locator.clear "supabase-migration"
  locator.clear "supabase-config"

  migrations.each_with_index do |sql, index|
    # Lexical order is chronological for Supabase migration filenames.
    path = File.tempname("#{index}_migration", ".sql")
    File.write(path, sql)
    paths << path
    locator.push "supabase-migration", path
  end

  if config
    path = File.tempname("config", ".toml")
    File.write(path, config)
    paths << path
    locator.push "supabase-config", path
  end

  options = create_test_options
  Analyzer::Specification::Supabase.new(options).analyze
ensure
  locator = CodeLocator.instance
  locator.clear "supabase-migration"
  locator.clear "supabase-config"
  paths.try &.each { |p| File.delete(p) if File.exists?(p) }
end

describe "Supabase Analyzer" do
  # PostgREST addresses rows with a filter, not a path segment, so a
  # /rest/v1/posts/{id} endpoint would be a wrong URL.
  it "emits four collection verbs and no item path" do
    endpoints = analyze_supabase("create table public.posts (id bigserial primary key, title text);")

    endpoints.map(&.url).uniq!.should eq(["/rest/v1/posts"])
    endpoints.map(&.method).sort!.should eq(["DELETE", "GET", "PATCH", "POST"])
    endpoints.none?(&.url.includes?("{")).should be_true
  end

  # Unlike Strapi/Directus/Payload, the bare column name IS the wire
  # query key under PostgREST (?id=eq.1).
  it "emits column names as query filters and as body params" do
    endpoints = analyze_supabase("create table public.posts (id bigserial primary key, title text, published boolean);")

    list = endpoints.find! { |e| e.method == "GET" }
    query_names = list.params.select { |p| p.param_type == "query" }.map(&.name)
    query_names.should contain("title")
    query_names.should contain("select")
    query_names.should contain("order")

    insert = endpoints.find! { |e| e.method == "POST" }
    body = insert.params.select { |p| p.param_type == "json" }
    body.map(&.name).should eq(["id", "title", "published"])
    body.find! { |p| p.name == "published" }.value.should eq("boolean")
  end

  it "carries the PostgREST auth headers" do
    endpoints = analyze_supabase("create table public.posts (id int);")

    insert = endpoints.find! { |e| e.method == "POST" }
    headers = insert.params.select { |p| p.param_type == "header" }.map(&.name)
    headers.should contain("apikey")
    headers.should contain("Authorization")
    headers.should contain("Prefer")
  end

  # Supabase migrations routinely create tables in internal schemas that
  # PostgREST never exposes.
  it "skips tables in internal schemas" do
    endpoints = analyze_supabase <<-SQL
      create table public.posts (id int);
      create table auth.audit_log (id int);
      create table storage.objects (id int);
      create table extensions.thing (id int);
      SQL

    endpoints.map(&.url).uniq!.should eq(["/rest/v1/posts"])
  end

  it "honours extra exposed schemas from config.toml" do
    endpoints = analyze_supabase(
      "create table public.posts (id int); create table storefront.products (id int);",
      config: "[api]\nschemas = [\"public\", \"storefront\"]\n"
    )

    urls = endpoints.map(&.url).uniq!
    urls.should contain("/rest/v1/posts")
    urls.should contain("/rest/v1/products")
  end

  it "emits views as read-only" do
    endpoints = analyze_supabase <<-SQL
      create table public.posts (id int, published boolean);
      create view public.published_posts as select id from public.posts where published;
      SQL

    view_endpoints = endpoints.select { |e| e.url == "/rest/v1/published_posts" }
    view_endpoints.size.should eq(1)
    view_endpoints.first.method.should eq("GET")
  end

  it "emits functions as rpc endpoints with their named arguments" do
    endpoints = analyze_supabase <<-SQL
      create table public.posts (id int);
      create or replace function public.search_posts(query text, max_results integer default 10)
      returns setof public.posts language sql as $$ select * from public.posts $$;
      SQL

    rpc = endpoints.find! { |e| e.url == "/rest/v1/rpc/search_posts" }
    rpc.method.should eq("POST")
    rpc.params.select { |p| p.param_type == "json" }.map(&.name).should eq(["query", "max_results"])
  end

  # A column added in one migration and dropped in another is not part
  # of the final surface.
  it "applies migrations in order rather than merging them" do
    endpoints = analyze_supabase(
      "create table public.posts (id int, body text, rating numeric);",
      "alter table public.posts add column slug text; alter table public.posts drop column body; alter table public.posts rename column rating to score;"
    )

    names = endpoints.find! { |e| e.method == "POST" }.params.select { |p| p.param_type == "json" }.map(&.name)
    names.should eq(["id", "score", "slug"])
  end

  it "returns nothing for a migration set with no exposed tables" do
    analyze_supabase("create table auth.only_internal (id int);").size.should eq(0)
  end
end
