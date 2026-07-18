require "../../../models/endpoint"

module Analyzer::Specification
  # Shared primitives for the schema-generated API analyzers (Strapi,
  # Directus, Payload, Supabase/PostgREST, Hasura, Appwrite).
  #
  # These platforms all derive their HTTP surface from a schema file
  # rather than from route declarations in source, so they share the
  # same building blocks: turn a resource name into CRUD URLs, turn a
  # attribute list into params, and tag the result.
  #
  # Deliberately primitives rather than a base class or a unified
  # `emit_crud`. The six diverge exactly where a shared CRUD routine
  # would have to commit: Hasura has no CRUD skeleton at all (GraphQL
  # only), PostgREST has no item URL (rows are addressed by filter),
  # and Payload/Appwrite carry large non-CRUD route families. Each
  # analyzer spells out its own verb sequence the way
  # `Analyzer::Specification::OData#emit_entity_set` does.
  module SchemaApiCommon
    extend self

    # Appends one endpoint, tagged so `--exclude`/filtering can target
    # a single platform or a single operation kind.
    def emit(sink : Array(Endpoint), url : String, method : String,
             params : Array(Param), details : Details,
             tag_name : String, tag_value : String, tag_source : String) : Endpoint
      endpoint = Endpoint.new(url, method, params, details)
      endpoint.add_tag(Tag.new(tag_name, tag_value, tag_source))
      sink << endpoint
      endpoint
    end

    # Dedups on (name, param_type), mirroring `Endpoint#push_param`.
    # Used while a param array is still being assembled, before the
    # `Endpoint` exists.
    def push_param_once(params : Array(Param), param : Param) : Nil
      return if param.name.empty?
      return if params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
      params << param
    end

    # `/:id` -> `/{id}`. Emit the brace form so the optimizer's
    # `add_path_parameters` pass picks the segment up: `normalize_url_shape`
    # only rewrites the colon form for insomnia/postman, so a `:id`
    # emitted here would survive verbatim into output.
    def normalize_colon_path(path : String) : String
      return path unless path.includes?(':')
      path.gsub(/:([A-Za-z_][A-Za-z0-9_]*)/) { "{#{$1}}" }
    end

    # Joins a mount prefix to a route path without doubling or dropping
    # the separator.
    def join_path(prefix : String, path : String) : String
      normalized_prefix = prefix.rstrip('/')
      return normalized_prefix.empty? ? "/" : normalized_prefix if path.empty? || path == "/"

      suffix = path.starts_with?('/') ? path : "/#{path}"
      result = "#{normalized_prefix}#{suffix}"
      result.empty? ? "/" : result
    end

    # Maps a platform type token to the small vocabulary Noir uses for
    # `Param#value` hints. Unknown types produce an empty hint rather
    # than a guess.
    def type_hint(raw : String, table : Hash(String, String)) : String
      table[raw.downcase]? || ""
    end
  end
end
