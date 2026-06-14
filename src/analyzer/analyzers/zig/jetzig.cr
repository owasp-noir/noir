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

    def analyze
      include_callee = callees_needed?

      all_files.each do |path|
        next unless path.ends_with?(".zig")
        next unless jetzig_view?(path)

        content = read_file_content(path)
        # A view file always references the framework (`*jetzig.Request`,
        # `!jetzig.View`); gate on it so an unrelated `.zig` file that
        # happens to live under an `app/views/` tree isn't mined for routes.
        next unless content.includes?("jetzig")

        process_view(path, content, include_callee)
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
