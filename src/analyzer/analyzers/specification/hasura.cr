require "../../../models/analyzer"
require "../../../utils/yaml"
require "./graphql_sdl_parser"
require "./schema_api_common"

module Analyzer::Specification
  # Hasura does *not* generate per-table REST routes. A tracked table
  # becomes a set of GraphQL root fields on `POST /v1/graphql`; the only
  # REST surface is whatever `metadata/rest_endpoints.yaml` declares.
  # Emitting `/api/rest/<table>` would invent endpoints that 404.
  #
  # Rather than re-deriving GraphQL handling, each tracked table is
  # rendered as a small SDL document and handed to `GraphqlSdlParser`.
  # That yields the fragment URL convention (`/v1/graphql#Query.movies`),
  # a runnable operation document per field, and input-object expansion
  # into dotted params — all of which the SDL analyzer already does.
  class Hasura < Analyzer
    include SchemaApiCommon

    GRAPHQL_PATH = "/v1/graphql"
    REST_PREFIX  = "/api/rest"
    TAG_SOURCE   = "hasura_analyzer"

    # Hasura's metadata carries no column list of its own; column-level
    # permissions are the only place columns are named.
    PERMISSION_KEYS = {
      "select_permissions", "insert_permissions",
      "update_permissions", "delete_permissions",
    }

    # Column names must be valid GraphQL identifiers to appear in the
    # synthesized SDL.
    GRAPHQL_IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]*\z/

    def analyze
      locator = CodeLocator.instance

      tables = locator.all("hasura-tables")
      if tables.is_a?(Array(String))
        tables.each do |path|
          next unless File.exists?(path)
          begin
            parse_tables(read_file_content(path), path)
          rescue e
            @logger.debug "Failed to parse Hasura table metadata #{path}"
            @logger.debug_sub e
          end
        end
      end

      rest = locator.all("hasura-rest-endpoints")
      if rest.is_a?(Array(String))
        rest.each do |path|
          next unless File.exists?(path)
          begin
            parse_rest_endpoints(read_file_content(path), path)
          rescue e
            @logger.debug "Failed to parse Hasura REST endpoints #{path}"
            @logger.debug_sub e
          end
        end
      end

      @result
    end

    private def parse_tables(content : String, source : String)
      data = parse_yaml(content)

      if entries = data.as_a?
        # Flat `tables.yaml`. The CLI v3 index form is an array of
        # `!include` strings, which carry no table and are skipped here.
        entries.each do |entry|
          node = entry.as_h?
          emit_table(node, source) if node
        end
        return
      end

      if root = data.as_h?
        emit_table(root, source)
      end
    end

    private def emit_table(node : Hash(YAML::Any, YAML::Any), source : String)
      table = node[YAML::Any.new("table")]?
      return unless table

      name, schema = table_identity(table)
      return unless name

      columns = permission_columns(node)
      # Non-public schemas are prefixed into the root field name by
      # Hasura's default naming convention.
      root_name = schema == "public" || schema.empty? ? name : "#{schema}_#{name}"
      return unless root_name.matches?(GRAPHQL_IDENTIFIER)

      sdl = build_sdl(root_name, columns)

      endpoints = GraphqlSdlParser.parse(sdl, source,
        default_path: GRAPHQL_PATH, tag_source: TAG_SOURCE)

      endpoints.each do |endpoint|
        # The parser reports positions inside the synthesized SDL, which
        # mean nothing against the YAML. Re-point them at the metadata
        # file itself.
        endpoint.details = Details.new(PathInfo.new(source))
        endpoint.add_tag(Tag.new("hasura", "table:#{schema}.#{name}", TAG_SOURCE))
        @result << endpoint
      end
    end

    private def table_identity(table : YAML::Any) : Tuple(String?, String)
      if node = table.as_h?
        name = node[YAML::Any.new("name")]?.try(&.as_s?)
        schema = node[YAML::Any.new("schema")]?.try(&.as_s?) || "public"
        return {name, schema}
      end

      # Shorthand: `table: users` means the public schema.
      if name = table.as_s?
        return {name, "public"}
      end

      {nil, "public"}
    end

    # Unions the columns named across every permission block. A table
    # with no permissions (admin-only) degrades to root fields with the
    # standard arguments and no column params.
    private def permission_columns(node : Hash(YAML::Any, YAML::Any)) : Array(String)
      columns = [] of String

      PERMISSION_KEYS.each do |key|
        entries = node[YAML::Any.new(key)]?.try(&.as_a?)
        next unless entries

        entries.each do |entry|
          rule = entry.as_h?
          next unless rule
          permission = rule[YAML::Any.new("permission")]?.try(&.as_h?)
          next unless permission
          listed = permission[YAML::Any.new("columns")]?
          next unless listed

          # `columns: '*'` grants everything without naming anything.
          next unless names = listed.as_a?
          names.each do |column|
            value = column.as_s?
            next unless value && value.matches?(GRAPHQL_IDENTIFIER)
            columns << value unless columns.includes?(value)
          end
        end
      end

      columns
    end

    # Renders the root fields Hasura generates for a tracked table. Input
    # object bodies are one field per line because `parse_input_fields`
    # is line-oriented.
    private def build_sdl(root_name : String, columns : Array(String)) : String
      has_pk = columns.includes?("id")

      String.build do |io|
        unless columns.empty?
          {"#{root_name}_insert_input", "#{root_name}_set_input", "#{root_name}_bool_exp"}.each do |input_name|
            io << "input " << input_name << " {\n"
            columns.each { |column| io << "  " << column << ": String\n" }
            io << "}\n"
          end
        end

        io << "type Query {\n"
        io << "  " << root_name << "(where: " << root_name << "_bool_exp, limit: Int, offset: Int, order_by: String, distinct_on: String): [" << root_name << "!]!\n"
        io << "  " << root_name << "_by_pk(id: ID!): " << root_name << "\n" if has_pk
        io << "  " << root_name << "_aggregate(where: " << root_name << "_bool_exp): " << root_name << "_aggregate_fields!\n"
        io << "}\n"

        io << "type Mutation {\n"
        io << "  insert_" << root_name << "(objects: [" << root_name << "_insert_input!]!, on_conflict: String): " << root_name << "_mutation_response\n"
        io << "  insert_" << root_name << "_one(object: " << root_name << "_insert_input!): " << root_name << "\n"
        io << "  update_" << root_name << "(where: " << root_name << "_bool_exp!, _set: " << root_name << "_set_input): " << root_name << "_mutation_response\n"
        io << "  update_" << root_name << "_by_pk(pk_columns: ID!, _set: " << root_name << "_set_input): " << root_name << "\n" if has_pk
        io << "  delete_" << root_name << "(where: " << root_name << "_bool_exp!): " << root_name << "_mutation_response\n"
        io << "  delete_" << root_name << "_by_pk(id: ID!): " << root_name << "\n" if has_pk
        io << "}\n"
      end
    end

    private def parse_rest_endpoints(content : String, source : String)
      entries = parse_yaml(content).as_a?
      return unless entries

      entries.each do |entry|
        node = entry.as_h?
        next unless node

        url = node[YAML::Any.new("url")]?.try(&.as_s?)
        next unless url

        methods = node[YAML::Any.new("methods")]?.try(&.as_a?)
        next unless methods

        name = node[YAML::Any.new("name")]?.try(&.as_s?) || url
        details = Details.new(PathInfo.new(source))
        full_url = join_path(REST_PREFIX, normalize_colon_path(url))

        methods.each do |method|
          verb = method.as_s?
          next unless verb
          emit(@result, full_url, verb.upcase, [] of Param, details, "hasura", "rest-endpoint:#{name}", TAG_SOURCE)
        end
      end
    end
  end
end
