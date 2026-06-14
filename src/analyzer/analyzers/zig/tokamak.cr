require "../../../models/analyzer"
require "../../../miniparsers/zig_callee_extractor"
require "../../../utils/url_path"

module Analyzer::Zig
  # Tokamak declares routes as a flat data structure of `tk.Route` values:
  #
  #   const routes: []const tk.Route = &.{
  #     .get("/", hello),
  #     .post("/users", createUser),
  #     .group("/api", &.{
  #       .get("/health", health),
  #     }),
  #   };
  #
  # `.group(prefix, &.{ … })` composes its prefix onto every nested route, so
  # the analyzer tracks brace nesting to accumulate prefixes. `.post0`/`.put0`/
  # `.patch0` are the body-less variants of the same verbs. The handler (second
  # argument) supplies the callees.
  class Tokamak < Analyzer
    VERB_METHOD = {
      "get" => "GET", "post" => "POST", "post0" => "POST", "put" => "PUT",
      "put0" => "PUT", "patch" => "PATCH", "patch0" => "PATCH",
      "delete" => "DELETE", "head" => "HEAD", "options" => "OPTIONS",
    }

    GROUP_RE = /\.\s*group\s*\(\s*"([^"]*)"\s*,\s*&?\s*\.\s*\{/
    ROUTE_RE = /\.\s*(get|post0|post|put0|put|patch0|patch|delete|head|options)\s*\(\s*"([^"]*)"\s*,\s*([A-Za-z_][\w.]*)/

    private record GroupFrame, prefix : String, close : Int32

    def analyze
      include_callee = callees_needed?

      all_files.each do |path|
        next unless path.ends_with?(".zig")
        content = read_file_content(path)
        next unless content.includes?("tokamak") || content.includes?("tk.Route") || content.includes?("Route")
        process_file(path, content, include_callee)
      end

      @result
    end

    private def process_file(path : String, content : String, include_callee : Bool)
      text = Noir::ZigCalleeExtractor.strip_comments(content)
      chars = text.chars
      bodies = include_callee ? Noir::ZigCalleeExtractor.function_bodies(content, path) : {} of String => Noir::ZigCalleeExtractor::FunctionBody

      events = collect_events(text, chars)
      stack = [] of GroupFrame

      events.each do |ev|
        stack.reject! { |frame| frame.close < ev[:off] }

        if ev[:kind] == :group
          close = ev[:close]
          stack << GroupFrame.new(ev[:prefix], close) if close
          next
        end

        prefix = stack.reduce("") { |acc, frame| Noir::URLPath.join(acc, frame.prefix) }
        url = Noir::URLPath.join(prefix, ev[:path])
        emit(path, text, ev[:off], url, ev[:method], ev[:handler], bodies, include_callee)
      end
    end

    # Group-open and route events, ordered by source offset, so a single pass
    # with a brace-keyed stack reconstructs the prefix in scope for each route.
    private def collect_events(text : String, chars : Array(Char))
      events = [] of NamedTuple(kind: Symbol, off: Int32, prefix: String, close: Int32?, path: String, method: String, handler: String)

      text.scan(GROUP_RE) do |m|
        brace_open = (m.end(0) || 0) - 1
        close = Noir::ZigCalleeExtractor.find_matching(chars, brace_open, '{', '}')
        events << {kind: :group, off: m.begin(0) || 0, prefix: m[1], close: close, path: "", method: "", handler: ""}
      end

      text.scan(ROUTE_RE) do |m|
        verb = m[1]
        method = VERB_METHOD[verb]?
        next if method.nil?
        events << {kind: :route, off: m.begin(0) || 0, prefix: "", close: nil, path: m[2], method: method, handler: m[3]}
      end

      events.sort_by { |ev| ev[:off] }
    end

    private def emit(path, text, offset, url, method, handler, bodies, include_callee)
      params = extract_path_params(url)
      line = Noir::ZigCalleeExtractor.line_at(text.chars, offset)
      details = Details.new(PathInfo.new(path, line))
      endpoint = Endpoint.new(url, method, params, details)

      if include_callee
        name = handler.includes?('.') ? handler.split('.').last : handler
        if body = bodies[name]?
          callees = Noir::ZigCalleeExtractor.callees_for_body(body[:body], body[:path], body[:start_line])
          Noir::ZigCalleeExtractor.attach_to(endpoint, callees) unless callees.empty?
        end
      end

      @result << endpoint
    end

    private def extract_path_params(url : String) : Array(Param)
      params = [] of Param
      url.scan(/:([A-Za-z_]\w*)/) do |m|
        params << Param.new(m[1], "", "path")
      end
      params
    end
  end
end
