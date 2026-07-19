require "../../engines/cfml_engine"

module Analyzer::Cfml
  # FW/1 (Framework One) routing.
  #
  # Routes live in `Application.cfc` as an array of single-key structs,
  # where the key is an optional `$METHOD` followed by the pattern:
  #
  #     variables.framework = {
  #         routes = [
  #             { "$GET/todo/:id"    = "/main/get/id/:id" },
  #             { "$DELETE/todo/:id" = "/main/delete/id/:id" },
  #             { "$POST/todo/"      = "/main/save" },
  #             { 'hint' = 'Resource Routes', '$RESOURCES' = 'dogs' }
  #         ]
  #     };
  #
  # A key with no `$` prefix answers every method. `hint` is a label the
  # framework skips, not a route.
  class Fw1 < CfmlEngine
    ROUTES_ARRAY_RE = /\broutes\s*[:=]\s*\[/i

    # `"$GET/todo/:id" = "/main/get/id/:id"` — the value is the internal
    # action, which is not part of the URL.
    ROUTE_ENTRY_RE = /["']([^"']+)["']\s*[:=]\s*["']([^"']*)["']/

    # `$METHOD` prefix on the pattern. `$*` means every method.
    METHOD_PREFIX_RE = /\A\$([A-Za-z*]+)/

    # `hint` labels the entry rather than declaring a route. Only keys
    # FW/1's own sources use as labels belong here — skipping a key the
    # framework does treat as a pattern is a silent false negative.
    NON_ROUTE_KEYS = Set{"hint"}

    RESOURCES_KEY = "$RESOURCES"

    # A key with no `$` prefix, or an explicit `$*`, answers every method.
    ALL_METHODS = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    # `framework/one.cfc` defines these as `resourceRouteTemplates`.
    # Note there is no `edit` route — FW/1 differs from Rails here.
    RESOURCE_TEMPLATES = [
      {["GET"], "", false},
      {["GET"], "/new", false},
      {["POST"], "", false},
      {["GET"], "", true},
      {["PUT", "PATCH"], "", true},
      {["DELETE"], "", true},
    ]

    def analyze
      candidates = cfml_components.select { |path| File.basename(path).downcase == "application.cfc" }
      return @result if candidates.empty?

      parallel_analyze(candidates) do |path|
        analyze_routes(path)
      end

      @result
    end

    private def analyze_routes(path : String)
      content = strip_all_comments(read_file_content(path))
      match = content.match(ROUTES_ARRAY_RE)
      return unless match

      open_bracket = content.index('[', match.begin(0) || 0)
      return unless open_bracket

      close_bracket = matching_bracket(content, open_bracket)
      return unless close_bracket

      body = content[(open_bracket + 1)...close_bracket]
      details = Details.new(PathInfo.new(path, line_number_for_index(content, open_bracket)))

      # Each element is its own `{ ... }` struct; scanning the array body
      # entry by entry keeps a `hint` label attached to the route it
      # labels rather than leaking across elements.
      split_arguments(body).each do |element|
        process_entry(element, details)
      end
    end

    private def process_entry(element : String, details : Details)
      element.scan(ROUTE_ENTRY_RE) do |match|
        key = match[1].strip
        value = match[2].strip

        next if NON_ROUTE_KEYS.includes?(key.downcase)

        if key.compare(RESOURCES_KEY, case_insensitive: true) == 0
          emit_resources(value, details)
          next
        end

        emit_route(key, details)
      end
    end

    private def emit_route(key : String, details : Details)
      methods = ALL_METHODS
      pattern = key

      if match = key.match(METHOD_PREFIX_RE)
        verb = match[1].upcase
        pattern = key[match.end(0)..]

        # `$*` keeps the full set; a named verb narrows to it.
        unless verb == "*"
          return unless HTTP_VERBS.includes?(verb)

          methods = [verb]
        end
      end

      url = normalize(pattern)
      return if url.empty?

      methods.each do |method|
        @result << Endpoint.new(url, method, [] of Param, details)
      end
    end

    # `'$RESOURCES' = 'dogs'` expands per the framework's
    # `resourceRouteTemplates`. The value may name several resources.
    private def emit_resources(value : String, details : Details)
      value.split(',').each do |entry|
        resource = entry.strip.strip('/')
        next if resource.empty?

        RESOURCE_TEMPLATES.each do |methods, suffix, include_id|
          url = normalize("/#{resource}#{include_id ? "/:id" : ""}#{suffix}")
          next if url.empty?

          methods.each do |method|
            @result << Endpoint.new(url, method, [] of Param, details)
          end
        end
      end
    end

    private def normalize(pattern : String) : String
      normalized = pattern.strip.gsub(/\/+/, "/")
      return "" if normalized.empty?

      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized = normalized.chomp('/') if normalized.size > 1
      normalized
    end
  end
end
