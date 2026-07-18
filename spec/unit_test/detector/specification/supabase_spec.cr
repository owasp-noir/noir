require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Supabase" do
  options = create_test_options
  instance = Detector::Specification::Supabase.new options

  schema = "create table public.posts (id bigserial primary key, title text);"

  it "detects a migration under supabase/" do
    instance.detect("supabase/migrations/20240101000000_init.sql", schema).should be_true
  end

  it "detects a migration in a nested supabase/ directory" do
    instance.detect("apps/web/supabase/migrations/001_init.sql", schema).should be_true
  end

  it "detects an alter-only migration" do
    content = "alter table public.posts add column slug text;"
    instance.detect("supabase/migrations/002_add_slug.sql", content).should be_true
  end

  it "detects supabase/config.toml" do
    instance.detect("supabase/config.toml", "project_id = \"demo\"\n[api]\nschemas = [\"public\"]").should be_true
  end

  it "accepts lowercase and IF NOT EXISTS forms" do
    instance.detect("supabase/migrations/a.sql", "create table if not exists public.a (id int);").should be_true
    instance.detect("supabase/migrations/b.sql", "CREATE TABLE public.b (id int);").should be_true
  end

  # CREATE TABLE is the most universal statement in SQL. Without a path
  # gate every schema dump in every repo would be claimed as a
  # PostgREST API.
  it "ignores a .sql file outside supabase/ and migrations/" do
    instance.detect("db/structure.sql", schema).should be_false
    instance.detect("schema.sql", schema).should be_false
    instance.detect("dump.sql", schema).should be_false
    instance.detect("test/fixtures/seed_schema.sql", schema).should be_false
  end

  # A migrations/ directory belongs to every migration tool there is, so
  # that tier needs a Supabase-specific fingerprint on top.
  it "ignores a Rails or Flyway migration with no Supabase fingerprint" do
    instance.detect("db/migrate/001_create_posts.sql", schema).should be_false
    instance.detect("src/main/resources/db/migration/V1__init.sql", schema).should be_false
  end

  it "accepts a migrations/ file that does carry an RLS fingerprint" do
    content = <<-SQL
      create table public.posts (id bigserial primary key);
      alter table public.posts enable row level security;
      create policy "read" on public.posts for select using (auth.uid() is not null);
      SQL

    instance.detect("db/migrations/001_init.sql", content).should be_true
  end

  it "ignores a seed file with no DDL" do
    content = "insert into public.authors (name) values ('noir');"
    instance.detect("supabase/seed.sql", content).should be_false
  end

  it "ignores a supabase .sql carrying only grants" do
    content = "grant select on public.posts to anon;"
    instance.detect("supabase/migrations/003_grants.sql", content).should be_false
  end

  it "ignores non-sql extensions" do
    instance.detect("supabase/migrations/init.txt", schema).should be_false
    instance.detect("supabase/functions/index.ts", schema).should be_false
  end

  # The gate is evaluated relative to the scan base, so a checkout that
  # merely lives under a directory named `supabase` does not turn every
  # .sql beneath it into a migration.
  it "ignores a supabase/ segment that belongs to the scan base" do
    scoped_options = create_test_options
    scoped_options["base"] = YAML::Any.new([YAML::Any.new("/src/supabase")])
    scoped = Detector::Specification::Supabase.new scoped_options

    scoped.detect("/src/supabase/packages/pg-meta/test/db/00-init.sql", schema).should be_false
    # A real migration directory inside that base still matches.
    scoped.detect("/src/supabase/examples/app/supabase/migrations/001.sql", schema).should be_true
  end

  it "registers migration paths in the code locator" do
    locator = CodeLocator.instance
    locator.clear "supabase-migration"
    instance.detect("supabase/migrations/20240101000000_init.sql", schema)
    locator.all("supabase-migration").should eq(["supabase/migrations/20240101000000_init.sql"])
  end
end
