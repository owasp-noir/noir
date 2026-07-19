require "../../engines/cfml_engine"

module Analyzer::Cfml
  # Wheels routing.
  #
  # Routes are one fluent chain in `config/routes.cfm`:
  #
  #     mapper()
  #         .get(name="login", pattern="login", to="sessions##new")
  #         .resources("users")
  #         .scope(path="admin", package="admin")
  #             .resources(name="users", nested=true)
  #                 .member()
  #                     .post("assume")
  #                 .end()
  #             .end()
  #         .end()
  #         .root(to="tweets##index", method="get")
  #     .end();
  #
  # The chain is order-dependent, so it is walked sequentially with a
  # prefix stack: `scope`, `namespace`, a nested `resources` and `member`
  # each push a path segment, and `end()` pops it. Without that, every
  # admin route would be emitted at the top level.
  class Wheels < CfmlEngine
    ROUTES_FILE = "routes.cfm"

    MAPPER_RE   = /(?<![\w.])mapper\s*\(/i
    DSL_CALL_RE = /\.\s*([A-Za-z_]\w*)\s*\(/
    UNESCAPE_RE = /##/
    # Wheels writes path variables in brackets, not colons.
    PLACEHOLDER_RE = /\[([A-Za-z_]\w*)\]/

    # Default key segment for a member route.
    KEY_SEGMENT = "[key]"

    VERB_CALLS = Set{"get", "post", "put", "patch", "delete", "head", "options"}

    # Wheels' plural resource set. `update` answers both PUT and PATCH.
    RESOURCES_ROUTES = [
      {"index", ["GET"], ""},
      {"new", ["GET"], "/new"},
      {"create", ["POST"], ""},
      {"show", ["GET"], "/[key]"},
      {"edit", ["GET"], "/[key]/edit"},
      {"update", ["PUT", "PATCH"], "/[key]"},
      {"delete", ["DELETE"], "/[key]"},
    ]

    # Singular `resource` has no index and no key segment — it always
    # acts on the one record implied by the session.
    RESOURCE_ROUTES = [
      {"new", ["GET"], "/new"},
      {"create", ["POST"], ""},
      {"show", ["GET"], ""},
      {"edit", ["GET"], "/edit"},
      {"update", ["PUT", "PATCH"], ""},
      {"delete", ["DELETE"], ""},
    ]

    def analyze
      routes_files = cfml_pages.select { |path| File.basename(path).downcase == ROUTES_FILE }
      return @result if routes_files.empty?

      parallel_analyze(routes_files) do |path|
        analyze_routes(path)
      end

      @result
    end

    private def analyze_routes(path : String)
      content = strip_all_comments(read_file_content(path))
      match = content.match(MAPPER_RE)
      return unless match

      walk_chain(content, path, match.end(0) || 0)
    end

    # Walk the fluent chain in source order, maintaining the path prefix
    # that `scope`/`namespace`/nested `resources`/`member` establish.
    private def walk_chain(content : String, path : String, from : Int32)
      # The base frame belongs to `mapper()` itself. Popping it is what
      # marks the end of the chain: `.get`/`.post`/`.delete` are ordinary
      # method names, and a routes file legitimately holds other setup
      # code, so anything outside these bounds is not a route.
      prefixes = [""]
      finished = false

      content.scan(DSL_CALL_RE) do |match|
        start = match.begin(0) || 0
        next if start < from || finished

        call = match[1].downcase

        open_paren = content.index('(', start)
        next unless open_paren

        close_paren = matching_paren(content, open_paren)
        next unless close_paren

        arguments = call_arguments(content[(open_paren + 1)...close_paren])
        prefix = prefixes.last
        line = line_number_for_index(content, start)

        case call
        when "end"
          prefixes.pop
          finished = prefixes.empty?
        when "scope", "namespace"
          segment = arguments["path"]? || arguments["name"]? || arguments["0"]?
          prefixes << join(prefix, segment || "")
        when "member"
          prefixes << prefix
        when "collection"
          # A collection block acts on the set, so it drops back to the
          # resource root that the enclosing `resources` pushed.
          prefixes << prefix.sub(/\/\[[^\]]+\]\z/, "")
        when "resources"
          name = arguments["name"]? || arguments["0"]?
          next if name.nil? || name.empty?

          base = join(prefix, arguments["path"]? || name)
          emit_resource_set(RESOURCES_ROUTES, base, arguments, path, line)
          # A nested resource scopes its children under its key.
          prefixes << join(base, KEY_SEGMENT) if truthy?(arguments["nested"]?)
        when "resource"
          name = arguments["name"]? || arguments["0"]?
          next if name.nil? || name.empty?

          base = join(prefix, arguments["path"]? || name)
          emit_resource_set(RESOURCE_ROUTES, base, arguments, path, line)
        when "root"
          emit(path, "/", (arguments["method"]? || "GET").upcase, line)
        when "wildcard"
          # Maps every controller/action pair. Emitting those would drown
          # the declared routes, so it is deliberately not expanded.
          next
        else
          next unless VERB_CALLS.includes?(call)

          # `pattern` is optional and falls back to the route name.
          pattern = arguments["pattern"]? || arguments["name"]? || arguments["0"]?
          next if pattern.nil? || pattern.empty?

          emit(path, join(prefix, pattern), call.upcase, line)
        end
      end
    end

    private def emit_resource_set(routes, base : String, arguments : Hash(String, String), path : String, line : Int32)
      only = name_set(arguments["only"]?)
      except = name_set(arguments["except"]?)

      routes.each do |action, methods, suffix|
        next if except.includes?(action)
        next if !only.empty? && !only.includes?(action)

        methods.each { |method| emit(path, "#{base}#{suffix}", method, line) }
      end
    end

    private def name_set(raw : String?) : Set(String)
      return Set(String).new if raw.nil?

      raw.split(',').map(&.strip.downcase).reject(&.empty?).to_set
    end

    private def truthy?(raw : String?) : Bool
      return false if raw.nil?

      raw.strip.downcase == "true"
    end

    private def emit(path : String, url : String, method : String, line : Int32)
      normalized = normalize(url)
      return if normalized.empty?
      return unless HTTP_VERBS.includes?(method)

      @result << Endpoint.new(normalized, method, [] of Param,
        Details.new(PathInfo.new(path, line)))
    end

    private def join(prefix : String, segment : String) : String
      trimmed = segment.strip.strip('/')
      return prefix if trimmed.empty?

      "#{prefix}/#{trimmed}"
    end

    # `[key]` is Wheels' placeholder spelling; rewrite it to the `:name`
    # form the optimizer already registers as a path param.
    private def normalize(url : String) : String
      normalized = url.gsub(PLACEHOLDER_RE) { ":#{$~[1]}" }
      normalized = normalized.gsub(/\/+/, "/")
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized = normalized.chomp('/') if normalized.size > 1
      normalized
    end
  end
end
