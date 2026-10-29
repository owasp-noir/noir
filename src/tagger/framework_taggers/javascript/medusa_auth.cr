require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../miniparsers/js_route_extractor"
require "../../../utils/js_literal_scanner"

@[Noir::TaggerFor(key: "medusa_auth", name: "Medusa Auth Tagger", desc: "Identifies Medusa routes covered by an authenticate() middleware matcher", order: 290)]
class MedusaAuthTagger < FrameworkTagger
  # `defineMiddlewares({ routes: [{ matcher, middlewares }] })`. A route
  # whose `middlewares` include `authenticate(...)` guards the endpoints
  # the matcher covers. A matcher that does not call `authenticate` does not.
  DEFINE_RE      = /defineMiddlewares\s*\(/
  ROUTES_RE      = /(?:^|[{,\s])routes\s*:\s*\[/
  MATCHER_RE     = /(?:^|[{,\s])matcher\s*:\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/
  METHODS_RE     = /(?:^|[{,\s])methods?\s*:\s*(\[[^\]]*\]|"[A-Z]+"|'[A-Z]+')/
  MIDDLEWARES_RE = /(?:^|[{,\s])middlewares\s*:\s*\[/
  AUTH_CALL_RE   = /(?<![\w$.])authenticate\s*\(/
  VERB_RE        = /\b(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b/

  # Empty `verbs` means every method. `call` is the `authenticate(...)` text.
  private record AuthMatcher, verbs : Array(String), pattern : String, call : String, path : String, line : Int32

  def self.target_techs : Array(String)
    ["js_medusa"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    matchers = auth_matchers
    endpoints.each do |endpoint|
      guard = matchers.find { |matcher| covers?(matcher, endpoint) }
      next unless guard

      endpoint.add_tag(Tag.new("auth", "Protected by #{guard.call}", "medusa_auth", guard.path, guard.line))
    end
    endpoints
  end

  private def auth_matchers : Array(AuthMatcher)
    found = [] of AuthMatcher
    get_files_by_basename("middlewares.ts").each do |path|
      relative = base_relative_path(path)
      next unless relative.includes?("/src/api/")
      next if relative.includes?("/node_modules/")

      content = read_file(path) || next
      code = Noir::JSRouteExtractor.strip_js_comments(content)
      code.scan(DEFINE_RE) do |match|
        open = (match.end(0) || 0) - 1
        next if open < 0

        close = Noir::JSLiteralScanner.find_matching_paren(code, open) || next
        parse_routes_arg(code[(open + 1)...close], code, path, found)
      end
    end
    found
  end

  private def parse_routes_arg(arg : String, file_code : String, path : String, into : Array(AuthMatcher))
    trimmed = arg.lstrip
    if trimmed.starts_with?('[')
      parse_route_objects(trimmed, file_code, path, into)
      return
    end

    arg.scan(ROUTES_RE) do |match|
      open = (match.end(0) || 0) - 1
      next if open < 0

      close = Noir::JSLiteralScanner.find_matching_bracket(arg, open) || next
      parse_route_objects(arg[(open + 1)...close], file_code, path, into)
    end
  end

  private def parse_route_objects(array_inner : String, file_code : String, path : String, into : Array(AuthMatcher))
    index = 0
    while index < array_inner.size
      unless array_inner[index] == '{'
        index += 1
        next
      end

      close = Noir::JSLiteralScanner.find_matching_brace(array_inner, index) || break
      object = array_inner[(index + 1)...close]
      if pattern = object_matcher(object)
        if call = authenticate_call(object)
          into << AuthMatcher.new(object_verbs(object), pattern, call, path, line_of(file_code, call))
        end
      end
      index = close + 1
    end
  end

  private def object_matcher(object : String) : String?
    match = object.match(MATCHER_RE) || return
    literal = match[1]
    return if literal.size < 2

    literal[1...-1]
  end

  private def object_verbs(object : String) : Array(String)
    match = object.match(METHODS_RE) || return [] of String
    verbs = [] of String
    match[1].scan(VERB_RE) do |hit|
      verbs << hit[1] unless verbs.includes?(hit[1])
    end
    verbs
  end

  private def authenticate_call(object : String) : String?
    match = object.match(MIDDLEWARES_RE) || return
    open = (match.end(0) || 0) - 1
    return if open < 0

    close = Noir::JSLiteralScanner.find_matching_bracket(object, open) || return
    list = object[(open + 1)...close]
    hit = list.match(AUTH_CALL_RE) || return
    paren = (hit.end(0) || 0) - 1
    return if paren < 0

    end_paren = Noir::JSLiteralScanner.find_matching_paren(list, paren) || return
    start = hit.begin(0) || 0
    list[start..(end_paren)].gsub(/\s+/, " ").strip
  end

  private def line_of(code : String, call : String) : Int32
    idx = code.index(call) || return 1
    code[0, idx].count('\n') + 1
  end

  private def covers?(matcher : AuthMatcher, endpoint : Endpoint) : Bool
    return false unless matcher.verbs.empty? || matcher.verbs.includes?(endpoint.method)

    pattern_covers?(matcher.pattern, endpoint.url)
  end

  # A single trailing `*` is the stem and paths nested under it.
  # `/admin/custom*` covers `/admin/custom` and `/admin/custom/child`,
  # not `/admin/customization`. `:id` and `{id}` are one path segment.
  private def pattern_covers?(pattern : String, url : String) : Bool
    return false if pattern.empty? || url.empty?

    if pattern.ends_with?('*') && pattern.count('*') == 1
      stem = pattern.rchop('*').rstrip('/')
      return true if stem.empty?

      bare = url.rstrip('/')
      return bare == stem || url.starts_with?(stem + "/")
    end

    left = pattern.split('/', remove_empty: true)
    right = url.split('/', remove_empty: true)
    return false unless left.size == right.size

    left.each_with_index do |segment, index|
      part = right[index]
      next if wildcard_segment?(segment) || wildcard_segment?(part)
      return false unless segment == part
    end
    true
  end

  private def wildcard_segment?(segment : String) : Bool
    segment == "*" || segment.starts_with?(':') || (segment.starts_with?('{') && segment.ends_with?('}'))
  end
end
