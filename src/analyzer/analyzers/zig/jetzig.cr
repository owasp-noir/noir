require "../../../models/analyzer"
require "../../../miniparsers/zig_callee_extractor"

module Analyzer::Zig
  # Jetzig uses filesystem-based "resourceful" routing (Rails-style). A view
  # file under `src/app/views/<name>.zig` is mounted at `/<name>`, and the
  # public function names inside it map to a fixed (HTTP method, URL-suffix)
  # table:
  #
  #   index  -> GET    /<name>
  #   get    -> GET    /<name>/:id
  #   new    -> GET    /<name>/new
  #   edit   -> GET    /<name>/:id/edit
  #   post   -> POST   /<name>
  #   put    -> PUT    /<name>/:id
  #   patch  -> PATCH  /<name>/:id
  #   delete -> DELETE /<name>/:id
  #
  # `root.zig` is special-cased to `/`. The view function body is the request
  # handler, so its 1-hop calls are surfaced as callees and `params.get("…")`
  # reads become query parameters.
  class Jetzig < Analyzer
    VIEWS_MARKER = "app#{File::SEPARATOR}views#{File::SEPARATOR}"

    # action => {http method, url suffix, has resource id}
    ACTIONS = {
      "index"  => {"GET", "", false},
      "get"    => {"GET", "/:id", true},
      "new"    => {"GET", "/new", false},
      "edit"   => {"GET", "/:id/edit", true},
      "post"   => {"POST", "", false},
      "put"    => {"PUT", "/:id", true},
      "patch"  => {"PATCH", "/:id", true},
      "delete" => {"DELETE", "/:id", true},
    }

    ACTION_FN_RE = /(?:^|[^A-Za-z0-9_.])pub\s+fn\s+(index|get|new|edit|post|put|patch|delete)\s*\(/
    PARAM_GET_RE = /\b(?:params|query)\s*\.\s*get\s*\(\s*"([^"]+)"/

    # Explicit custom route registered in the app's startup hook, e.g.
    #   app.route(.GET, "/api/products/:id", @import("app/api/products.zig"), .get);
    # The view module lives outside `app/views/` (so resourceful routing never
    # sees it) and the action is named by the trailing `.<action>` enum literal.
    CUSTOM_ROUTE_RE = /\.\s*route\s*\(\s*\.\s*(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|CONNECT|TRACE)\s*,\s*"(\/[^"]*)"\s*,\s*@import\s*\(\s*"([^"]+\.zig)"\s*\)\s*,\s*\.\s*(\w+)\s*\)/

    def analyze
      include_callee = callees_needed?

      all_files.each do |path|
        next unless path.ends_with?(".zig")
        next if Noir::ZigCalleeExtractor.vendored_framework_path?(path)

        content = read_file_content(path)

        # A view file always references the framework (`*jetzig.Request`,
        # `!jetzig.View`); gate on it so an unrelated `.zig` file that
        # happens to live under an `app/views/` tree isn't mined for routes.
        if jetzig_view?(path) && content.includes?("jetzig")
          process_view(path, content, include_callee)
        end

        # Explicit `app.route(...)` registrations live in the startup file
        # (`main.zig`), not under `app/views/`.
        process_custom_routes(path, content, include_callee) if content.includes?(".route(")
      end

      @result
    end

    private def jetzig_view?(path : String) : Bool
      path.includes?(VIEWS_MARKER)
    end

    private def process_view(path : String, content : String, include_callee : Bool)
      resource = resource_for(path)
      return if resource.nil?

      stripped = Noir::ZigCalleeExtractor.strip_non_code(content)
      # Strings preserved — `params.get("foo")` reads need the literal name.
      comment_stripped = Noir::ZigCalleeExtractor.strip_comments(content)
      table = Noir::ZigCalleeExtractor.function_table(content, path)
      by_name = {} of String => Noir::ZigCalleeExtractor::FunctionInfo
      table.each { |info| by_name[info[:name]] ||= info }

      stripped.scan(ACTION_FN_RE) do |match|
        action = match[1]
        spec = ACTIONS[action]?
        next if spec.nil?
        method, suffix, has_id = spec

        url = build_url(resource, suffix)
        line = Noir::ZigCalleeExtractor.line_at(stripped.chars, match.begin(0) || 0)
        details = Details.new(PathInfo.new(path, line))

        params = [] of Param
        params << Param.new("id", "", "path") if has_id

        info = by_name[action]?
        if info
          body_with_strings = comment_stripped[(info[:open] + 1)...info[:close]]? || ""
          params.concat(extract_params(body_with_strings))
        end

        endpoint = Endpoint.new(url, method, params, details)

        if include_callee && info
          callees = Noir::ZigCalleeExtractor.callees_for_body(info[:body], path, info[:start_line])
          Noir::ZigCalleeExtractor.attach_to(endpoint, callees) unless callees.empty?
        end

        @result << endpoint
      end
    end

    # Explicit `app.route(.VERB, "/path", @import("view.zig"), .action)`
    # registrations. The path is taken verbatim (with `:param` placeholders),
    # the verb from the enum literal, and 1-hop callees from the named action
    # function in the imported view module (which lives outside `app/views/`,
    # so it is resolved cross-file here).
    private def process_custom_routes(path : String, content : String, include_callee : Bool)
      text = Noir::ZigCalleeExtractor.strip_comments(content)
      dir = File.dirname(path)

      text.scan(CUSTOM_ROUTE_RE) do |m|
        method = m[1]
        url = m[2]
        import_rel = m[3]
        action = m[4]

        line = Noir::ZigCalleeExtractor.line_at(text.chars, m.begin(0) || 0)
        endpoint = Endpoint.new(url, method, path_params(url), Details.new(PathInfo.new(path, line)))

        if include_callee
          view_path = File.expand_path(File.join(dir, import_rel))
          action_callees(view_path, action).tap do |callees|
            Noir::ZigCalleeExtractor.attach_to(endpoint, callees) unless callees.empty?
          end
        end

        @result << endpoint
      end
    end

    # 1-hop callees of the named action function inside an `@import`-ed view
    # module. Returns empty when the file or function can't be resolved.
    private def action_callees(view_path : String, action : String) : Array(Noir::ZigCalleeExtractor::Entry)
      return [] of Noir::ZigCalleeExtractor::Entry unless view_path.ends_with?(".zig") && File.file?(view_path)
      content = read_file_content(view_path)
      bodies = Noir::ZigCalleeExtractor.function_bodies(content, view_path)
      if body = bodies[action]?
        return Noir::ZigCalleeExtractor.callees_for_body(body[:body], body[:path], body[:start_line])
      end
      [] of Noir::ZigCalleeExtractor::Entry
    end

    private def path_params(url : String) : Array(Param)
      params = [] of Param
      url.scan(/:([A-Za-z_]\w*)/) do |m|
        params << Param.new(m[1], "", "path")
      end
      params
    end

    # Resource path = the view file path below `app/views/`, extension
    # stripped, OS separators normalised to `/`. `root` collapses to the
    # site root.
    private def resource_for(path : String) : String?
      idx = path.rindex(VIEWS_MARKER)
      return if idx.nil?
      rel = path[(idx + VIEWS_MARKER.size)..]
      rel = rel[0...-4] if rel.ends_with?(".zig")
      rel = rel.gsub(File::SEPARATOR, "/")
      rel
    end

    # `base` is either empty (root) or `/<resource>` (never trailing-slash),
    # and every suffix is empty or leading-slash, so the concatenation is
    # already free of double slashes.
    private def build_url(resource : String, suffix : String) : String
      base = resource == "root" ? "" : "/#{resource}"
      url = "#{base}#{suffix}"
      url.empty? ? "/" : url
    end

    private def extract_params(body : String) : Array(Param)
      params = [] of Param
      body.scan(PARAM_GET_RE) do |match|
        name = match[1]
        next if name.empty?
        params << Param.new(name, "", "query")
      end
      params
    end
  end
end
