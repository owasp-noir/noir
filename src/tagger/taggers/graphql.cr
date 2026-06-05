require "../../models/tagger"
require "../../models/endpoint"

class GraphqlTagger < Tagger
  WORDS = ["query", "mutation", "subscription", "operationname", "__schema", "__type", "graphql", "variables"]

  # Strong, near-unique introspection signals: tagging on either alone is
  # safe because `__schema`/`__type` are GraphQL meta-fields, not names
  # that show up in REST inputs.
  INTROSPECTION_NAMES = Set{"__schema", "__type"}

  # Param names that plausibly carry a raw GraphQL document, so a value
  # that looks like a query/selection set is decisive even on a generic
  # URL like `/api`. Keeping the set tight avoids scanning unrelated
  # values (a JSON body, a search string) for GraphQL syntax.
  BODY_PARAM_NAMES = Set{"query", "mutation", "subscription", "graphql", "gql"}

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "graphql"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      names = endpoint.params.map(&.name.to_s.downcase)
      names_set = Set.new(names)

      intersection = Set.new(WORDS) & names_set

      url_lower = endpoint.url.downcase
      # `graphql` is distinctive enough as a substring; `gql` is too short
      # to match loosely (e.g. `/gqlgen`-style strings), so anchor it to a
      # path segment boundary.
      is_graphql_url = url_lower.includes?("graphql") || !!url_lower.match(%r{/gql(\b|/|\z)})

      introspection = names_set.any? { |name| INTROSPECTION_NAMES.includes?(name) }

      has_graphql_body = endpoint.params.any? do |param|
        BODY_PARAM_NAMES.includes?(param.name.to_s.downcase) && graphql_document_value?(param.value)
      end

      # Tag on any decisive signal (URL, introspection field, a body that
      # parses as a GraphQL document) or on two or more GraphQL-shaped
      # parameter names together (e.g. `query` + `variables`).
      check = is_graphql_url || introspection || has_graphql_body || intersection.size >= 2

      if check
        tag = Tag.new("graphql", "GraphQL endpoint for flexible API queries, potentially exposing schema introspection and nested data access.", "GraphQL")
        endpoint.add_tag(tag)
      end
    end
  end

  # Heuristic for "this value is a GraphQL document". Matches a named
  # operation (`query Foo { ... }`, `mutation { ... }`) or an anonymous
  # selection set (`{ users { id } }`) while deliberately rejecting JSON
  # objects (`{"a": 1}`) so a generic JSON body parameter isn't mistaken
  # for a query.
  private def graphql_document_value?(value : String) : Bool
    return false if value.empty?
    v = value.strip
    return false if v.empty?

    return true if v.matches?(/\A(query|mutation|subscription)\b[\s\S]*\{/i)

    if v.starts_with?("{") && !v.matches?(/\A\{\s*"/)
      return true if v.matches?(/\{[^{}]*\{/)
    end

    false
  end
end
