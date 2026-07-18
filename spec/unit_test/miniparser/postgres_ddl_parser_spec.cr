require "../../spec_helper"
require "../../../src/miniparsers/postgres_ddl_parser"

private def parse_ddl(sql : String)
  Noir::PostgresDdlParser.parse(sql, "migration.sql")
end

private def columns_of(state, key : String) : Array(String)
  state.tables[key].columns.map(&.name)
end

describe "Noir::PostgresDdlParser" do
  it "reads a schema-qualified create table" do
    state = parse_ddl <<-SQL
      create table public.posts (
        id bigserial primary key,
        title text not null
      );
      SQL

    state.tables.keys.should eq(["public.posts"])
    columns_of(state, "public.posts").should eq(["id", "title"])
  end

  it "defaults an unqualified table to the public schema" do
    state = parse_ddl("create table posts (id int);")
    state.tables.has_key?("public.posts").should be_true
  end

  it "accepts IF NOT EXISTS and the table variants" do
    state = parse_ddl <<-SQL
      create table if not exists public.a (id int);
      create unlogged table public.b (id int);
      create temporary table public.c (id int);
      SQL

    state.tables.keys.sort!.should eq(["public.a", "public.b", "public.c"])
  end

  # A depth counter is what keeps these from splitting mid-definition.
  it "survives parenthesised types and inline constraints" do
    state = parse_ddl <<-SQL
      create table public.orders (
        id uuid primary key default gen_random_uuid(),
        amount numeric(10, 2) not null,
        author_id uuid references public.authors (id) on delete cascade,
        status text check (status in ('open', 'closed')),
        constraint amount_positive check (amount > 0),
        primary key (id)
      );
      SQL

    columns_of(state, "public.orders").should eq(["id", "amount", "author_id", "status"])
  end

  it "captures multi-word and quoted column types" do
    state = parse_ddl <<-SQL
      create table public.events (
        "userId" uuid,
        created_at timestamp with time zone default now(),
        weight double precision,
        label character varying(255),
        tags text[]
      );
      SQL

    table = state.tables["public.events"]
    table.columns.map(&.name).should eq(["userId", "created_at", "weight", "label", "tags"])
    table.columns.find! { |c| c.name == "created_at" }.hint.should eq("datetime")
    table.columns.find! { |c| c.name == "weight" }.hint.should eq("number")
    table.columns.find! { |c| c.name == "label" }.hint.should eq("string")
    table.columns.find! { |c| c.name == "tags" }.hint.should eq("array")
  end

  it "omits generated-always-stored columns, which cannot be written" do
    state = parse_ddl <<-SQL
      create table public.posts (
        title text,
        search_vector tsvector generated always as (to_tsvector('english', title)) stored
      );
      SQL

    columns_of(state, "public.posts").should eq(["title"])
  end

  # Function bodies contain semicolons and DDL-looking text. Without
  # dollar-quote masking, one function shreds the statement split.
  it "masks dollar-quoted function bodies" do
    state = parse_ddl <<-SQL
      create table public.posts (id int);

      create or replace function public.search_posts(query text, max_results integer default 10)
      returns setof public.posts
      language plpgsql
      as $$
      begin
        -- create table decoy (id int);
        return query select * from public.posts limit max_results;
      end;
      $$;

      create table public.tags (id int);
      SQL

    state.tables.keys.sort!.should eq(["public.posts", "public.tags"])
    state.tables.has_key?("public.decoy").should be_false
    state.functions["public.search_posts"].arguments.map(&.name).should eq(["query", "max_results"])
  end

  it "handles a named dollar-quote tag" do
    state = parse_ddl <<-SQL
      create function public.f() returns void language plpgsql as $body$
      begin
        create table public.should_not_appear (id int);
      end;
      $body$;

      create table public.real_table (id int);
      SQL

    state.tables.keys.should eq(["public.real_table"])
  end

  it "ignores DDL inside line, block and nested block comments" do
    state = parse_ddl <<-SQL
      -- create table public.commented_out (id int);
      /* create table public.block_comment (id int);
         /* nested */
         still a comment: create table public.nested (id int);
      */
      create table public.real_table (id int);
      SQL

    state.tables.keys.should eq(["public.real_table"])
  end

  it "ignores DDL inside string literals, including doubled quotes" do
    state = parse_ddl <<-SQL
      create table public.notes (
        body text default 'create table public.from_string (id int); it''s fine'
      );
      SQL

    state.tables.keys.should eq(["public.notes"])
  end

  it "applies alter table add, drop and rename in order" do
    state = Noir::PostgresDdlParser::State.new
    Noir::PostgresDdlParser.apply("create table public.posts (id int, body text, rating numeric);", "a.sql", state)
    Noir::PostgresDdlParser.apply(<<-SQL, "b.sql", state)
      alter table public.posts add column slug text;
      alter table public.posts drop column body;
      alter table public.posts rename column rating to score;
      SQL

    columns_of(state, "public.posts").should eq(["id", "score", "slug"])
  end

  it "applies alter table rename to" do
    state = Noir::PostgresDdlParser::State.new
    Noir::PostgresDdlParser.apply("create table public.old_name (id int);", "a.sql", state)
    Noir::PostgresDdlParser.apply("alter table public.old_name rename to new_name;", "b.sql", state)

    state.tables.keys.should eq(["public.new_name"])
  end

  it "does not treat add constraint as a column" do
    state = Noir::PostgresDdlParser::State.new
    Noir::PostgresDdlParser.apply("create table public.posts (id int);", "a.sql", state)
    Noir::PostgresDdlParser.apply("alter table public.posts add constraint pk primary key (id);", "b.sql", state)

    columns_of(state, "public.posts").should eq(["id"])
  end

  it "drops tables" do
    state = Noir::PostgresDdlParser::State.new
    Noir::PostgresDdlParser.apply("create table public.a (id int); create table public.b (id int);", "a.sql", state)
    Noir::PostgresDdlParser.apply("drop table if exists public.a;", "b.sql", state)

    state.tables.keys.should eq(["public.b"])
  end

  it "marks views so callers can keep them read-only" do
    state = parse_ddl <<-SQL
      create table public.posts (id int, published boolean);
      create view public.published_posts as select id from public.posts where published;
      create materialized view public.stats as select count(*) from public.posts;
      SQL

    state.tables["public.published_posts"].view?.should be_true
    state.tables["public.stats"].view?.should be_true
    state.tables["public.posts"].view?.should be_false
  end

  it "records the originating line for each table" do
    state = parse_ddl <<-SQL
      -- leading comment
      create table public.first (id int);

      create table public.second (id int);
      SQL

    state.tables["public.first"].line.should eq(2)
    state.tables["public.second"].line.should be > state.tables["public.first"].line
  end

  it "returns nothing for a statement-free document" do
    parse_ddl("insert into public.a values (1);").tables.should be_empty
  end
end
