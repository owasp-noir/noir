require "../../../models/analyzer"
require "../../../miniparsers/postgres_ddl_parser"
require "./schema_api_common"

module Analyzer::Specification
  # Supabase serves PostgREST at `/rest/v1/`, exposing one resource per
  # table or view in an exposed schema.
  #
  # Two things make this differ from the other CRUD analyzers:
  #
  #   * There is no `/rest/v1/<table>/<id>` path. PostgREST addresses
  #     rows with a filter (`?id=eq.1`), so every verb lands on the
  #     collection URL and the column names *are* valid query keys.
  #   * Only exposed schemas are reachable. Supabase migrations routinely
  #     create tables in `auth`, `storage` and `extensions`, none of
  #     which PostgREST serves.
  class Supabase < Analyzer
    include SchemaApiCommon

    REST_PREFIX = "/rest/v1"
    TAG_SOURCE  = "supabase_analyzer"

    # PostgREST's default exposed schema. Supabase adds `graphql_public`,
    # which carries no user tables.
    DEFAULT_EXPOSED_SCHEMAS = {"public"}

    # Internal schemas that appear in migrations but are never served.
    INTERNAL_SCHEMAS = {
      "auth", "storage", "extensions", "graphql", "graphql_public",
      "realtime", "vault", "net", "cron", "pgsodium", "pgbouncer",
      "supabase_functions", "supabase_migrations", "information_schema",
      "pg_catalog",
    }

    MAX_FILTER_PARAMS = 25

    def analyze
      locator = CodeLocator.instance
      migrations = locator.all("supabase-migration")
      return @result unless migrations.is_a?(Array(String))

      exposed = exposed_schemas(locator.all("supabase-config"))

      # Migration filenames are `<timestamp>_<name>.sql`, so lexical order
      # is chronological. Applying them in order is what makes a column
      # added in one file and dropped in another come out right.
      state = Noir::PostgresDdlParser::State.new
      migrations.sort.each do |path|
        next unless File.exists?(path)
        begin
          Noir::PostgresDdlParser.apply(read_file_content(path), path, state)
        rescue e
          @logger.debug "Failed to parse Supabase migration #{path}"
          @logger.debug_sub e
        end
      end

      state.tables.each_value do |table|
        next unless served?(table.schema, exposed)
        emit_table(table)
      end

      state.functions.each_value do |function|
        next unless served?(function.schema, exposed)
        emit_function(function)
      end

      @result
    end

    private def exposed_schemas(configs) : Set(String)
      schemas = Set(String).new
      DEFAULT_EXPOSED_SCHEMAS.each { |s| schemas << s }
      return schemas unless configs.is_a?(Array(String))

      configs.each do |path|
        next unless File.exists?(path)
        begin
          content = read_file_content(path)
          # `[api]` block: `schemas = ["public", "storefront"]`
          if match = /^\s*schemas\s*=\s*\[([^\]]*)\]/m.match(content)
            match[1].split(',').each do |raw|
              name = raw.strip.strip('"').strip('\'')
              schemas << name unless name.empty?
            end
          end
        rescue e
          @logger.debug "Failed to read Supabase config #{path}"
          @logger.debug_sub e
        end
      end

      schemas
    end

    private def served?(schema : String, exposed : Set(String)) : Bool
      return false if INTERNAL_SCHEMAS.includes?(schema)
      exposed.includes?(schema)
    end

    private def emit_table(table : Noir::PostgresDdlParser::Table)
      url = "#{REST_PREFIX}/#{table.name}"
      details = Details.new(PathInfo.new(table.source, table.line))
      kind = table.view? ? "view" : "table"

      # Under PostgREST the column name is the query key, so unlike the
      # other schema-generated platforms the bare names are correct here.
      filters = [] of Param
      table.columns.each do |column|
        break if filters.size >= MAX_FILTER_PARAMS
        push_param_once(filters, Param.new(column.name, column.hint, "query"))
      end

      body = table.columns.map { |column| Param.new(column.name, column.hint, "json") }

      emit(@result, url, "GET", vertical_filtering + filters, details, "supabase", "#{kind}-select:#{table.name}", TAG_SOURCE)
      # A view is not writable through PostgREST without a trigger, so
      # only the read verb is emitted for one.
      return if table.view?

      emit(@result, url, "POST", body.dup + write_headers, details, "supabase", "table-insert:#{table.name}", TAG_SOURCE)
      emit(@result, url, "PATCH", body.dup + filters + write_headers, details, "supabase", "table-update:#{table.name}", TAG_SOURCE)
      emit(@result, url, "DELETE", filters.dup + auth_headers, details, "supabase", "table-delete:#{table.name}", TAG_SOURCE)
    end

    private def emit_function(function : Noir::PostgresDdlParser::Function)
      url = "#{REST_PREFIX}/rpc/#{function.name}"
      details = Details.new(PathInfo.new(function.source, function.line))
      params = function.arguments.map { |argument| Param.new(argument.name, argument.hint, "json") }

      emit(@result, url, "POST", params + auth_headers, details, "supabase", "rpc:#{function.name}", TAG_SOURCE)
    end

    # PostgREST's own query vocabulary, valid on every read.
    private def vertical_filtering : Array(Param)
      ["select", "order", "limit", "offset", "on_conflict"].map do |name|
        Param.new(name, "", "query")
      end
    end

    private def auth_headers : Array(Param)
      [
        Param.new("apikey", "", "header"),
        Param.new("Authorization", "", "header"),
      ]
    end

    private def write_headers : Array(Param)
      auth_headers + [Param.new("Prefer", "", "header")]
    end
  end
end
