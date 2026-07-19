require "../../engines/cfml_engine"

module Analyzer::Cfml
  # Taffy REST resources.
  #
  # Taffy is the most declarative of the CFML frameworks: a resource CFC
  # carries its path as a component-level attribute, and the HTTP verb is
  # the *name* of the handler function. Path, method and parameters are
  # therefore all statically known.
  #
  #     <cfcomponent extends="taffy.core.resource" taffy_uri="/artist/{id}">
  #         <cffunction name="get">
  #             <cfargument name="id" type="string" required="true">
  #
  #     component extends="taffy.core.resource" taffy:uri="/echo" {
  #         function post(string name = "", string value = "") {}
  class Taffy < CfmlEngine
    # Both spellings are officially supported — `taffy/core/api.cfc`
    # reads `taffy_uri` and falls back to `taffy:uri`.
    URI_ATTRIBUTES  = ["taffy_uri", "taffy:uri"]
    VERB_ATTRIBUTES = ["taffy_verb", "taffy:verb"]

    # Taffy dispatches an incoming request to the function named after
    # the HTTP verb.
    VERB_FUNCTIONS = Set{"get", "post", "put", "delete", "head", "options", "patch"}

    # Verbs whose arguments arrive in the query string rather than a body.
    QUERY_VERBS = Set{"GET", "HEAD", "OPTIONS", "DELETE"}

    RESOURCE_BASE_RE = /extends\s*=\s*["'][^"']*\bresource\b["']/i
    PATH_TOKEN_RE    = /\{([^}]+)\}/

    # `function name(...) taffy_verb="PATCH" {` — the attribute sits
    # between the closing paren and the body brace. The window is bounded
    # because slicing the whole remaining file per declaration made the
    # pass O(n^2) in file size.
    SCRIPT_FUNCTION_TAIL_RE    = /\A[^{;]*/
    SCRIPT_FUNCTION_TAIL_LIMIT = 200

    def analyze
      parallel_analyze(cfml_components) do |path|
        analyze_resource(path)
      end

      @result
    end

    private def analyze_resource(path : String)
      raw = read_file_content(path)
      return unless raw.includes?("taffy") || raw.matches?(RESOURCE_BASE_RE)

      content = strip_cfml_comments(raw)
      attributes = component_attributes(content)

      uris = resource_uris(attributes)
      return if uris.empty?

      handlers = tag_handlers(content) + script_handlers(content)
      return if handlers.empty?

      handlers.each do |handler|
        uris.each do |uri|
          emit(path, uri, handler)
        end
      end
    end

    # One CFC may declare several comma-separated URIs; `api.cfc` runs the
    # attribute through `splitURIs()` before registering.
    private def resource_uris(attributes : Hash(String, String)) : Array(String)
      raw = URI_ATTRIBUTES.compact_map { |name| attributes[name]? }.find { |value| !value.empty? }
      return [] of String if raw.nil?

      raw.split(',').compact_map do |uri|
        normalized = uri.strip
        next if normalized.empty?

        normalized.starts_with?("/") ? normalized : "/#{normalized}"
      end
    end

    private record Handler, method : String, params : Array(String), line : Int32

    private def tag_handlers(content : String) : Array(Handler)
      handlers = [] of Handler
      return handlers unless content.includes?("<cffunction") || content.includes?("<CFFUNCTION")

      content.scan(CFFUNCTION_TAG_RE) do |match|
        attributes = tag_attributes(match[1])
        name = attributes["name"]?
        next if name.nil? || name.empty?

        method = handler_method(name, attributes)
        next unless method

        tag_end = match.end(0)
        next unless tag_end

        handlers << Handler.new(method, tag_arguments(content, tag_end),
          line_number_for_index(content, match.begin(0) || 0))
      end

      handlers
    end

    private def script_handlers(content : String) : Array(Handler)
      handlers = [] of Handler

      content.scan(SCRIPT_FUNCTION_RE) do |match|
        name = match[1]
        start = match.begin(0) || 0

        open_paren = content.index('(', start)
        next unless open_paren

        close_paren = matching_paren(content, open_paren)
        next unless close_paren

        arguments = content[(open_paren + 1)...close_paren]

        # Only the signature tail up to the body brace may carry the verb
        # override; scanning further would pick up a later declaration's.
        tail = content[(close_paren + 1), SCRIPT_FUNCTION_TAIL_LIMIT]? || ""
        tail_match = tail.match(SCRIPT_FUNCTION_TAIL_RE)
        attributes = tag_attributes(tail_match ? tail_match[0] : "")

        method = handler_method(name, attributes)
        next unless method

        handlers << Handler.new(method, script_arguments(arguments),
          line_number_for_index(content, start))
      end

      handlers
    end

    # An explicit `taffy_verb` wins; otherwise the function name is the
    # verb, and a function named anything else is not a handler.
    private def handler_method(name : String, attributes : Hash(String, String)) : String?
      override = VERB_ATTRIBUTES.compact_map { |key| attributes[key]? }.first?
      if override && !override.empty?
        verb = override.strip.upcase
        return HTTP_VERBS.includes?(verb) ? verb : nil
      end

      normalized = name.downcase
      return unless VERB_FUNCTIONS.includes?(normalized)

      normalized.upcase
    end

    private def emit(path : String, uri : String, handler : Handler)
      # `{token}` placeholders are path params, and the optimizer already
      # registers them from the URL. Taffy also passes each token to the
      # handler as an argument, so dropping them here keeps a token from
      # surfacing twice — once as `path`, once as `query`.
      tokens = uri.scan(PATH_TOKEN_RE).map(&.[1].downcase).to_set

      location = QUERY_VERBS.includes?(handler.method) ? "query" : "form"
      params = handler.params
        .reject { |name| tokens.includes?(name.downcase) }
        .map { |name| Param.new(name, "", location) }

      details = Details.new(PathInfo.new(path, handler.line))
      @result << Endpoint.new(uri, handler.method, params, details)
    end
  end
end
