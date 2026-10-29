require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../utils/c_comments"
require "../../../utils/js_literal_scanner"

@[Noir::TaggerFor(key: "adonisjs_auth", name: "AdonisJS Auth Tagger", desc: "Identifies AdonisJS routes and route groups behind the auth middleware", order: 280)]
class AdonisjsAuthTagger < FrameworkTagger
  # The auth middleware on a route or group chain: v6 `.use(middleware.auth())`
  # (alone or first in a list, with or without `{ guards: [...] }`), v5
  # `.middleware('auth')` / `.middleware(['auth:api'])`, and a resource's
  # for all its actions (`.use('*', ...)`, v5 `.middleware({ '*': ['auth'] })`).
  # `silentAuth` and `guest` let anonymous callers through, and a
  # resource's per-action `.use(['store'], ...)` covers only some of its
  # routes, so neither counts.
  AUTH_USE   = /\.\s*use\s*\(\s*(?:['"]\*['"]\s*,\s*)?(?:\[\s*)?middleware\s*\.\s*auth\s*\(|\.\s*middleware\s*\(\s*(?:\{\s*['"]\*['"]\s*:\s*)?(?:\[\s*)?['"]auth(?::[\w,]+)?['"]/
  GROUP_CALL = /\.\s*group\s*\(/
  # A call chained on at the match position: `.prefix('/api')`.
  CHAINED_CALL = /\G\s*\.\s*[A-Za-z_$][\w$]*\s*\(/

  # A routes file with comments blanked (layout kept, so offsets and lines
  # are the file's), its chars, each line's offset, and every group call's
  # `{open paren, close paren, chain after it}`.
  private record RoutesFile, code : String, chars : Array(Char), offsets : Array(Int32), groups : Array({Int32, Int32, String})

  def self.target_techs : Array(String)
    ["js_adonisjs"]
  end

  def initialize(options : Hash(String, YAML::Any))
    super
    @files = Hash(String, RoutesFile?).new
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @files.clear
    super
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      line = path_info.line || next
      file = routes_file(path_info.path) || next
      next unless line >= 1 && line <= file.offsets.size
      at = file.offsets[line - 1]
      # ponytail: the first call on the route's line; a second route on the
      # same line reads the first one's chain.
      if (open = file.code.index('(', at)) && (close = Noir::JSLiteralScanner.find_matching_paren(file.chars, open)) &&
         chain(file, close + 1).matches?(AUTH_USE)
        endpoint.add_tag(Tag.new("auth", "Protected by AdonisJS middleware.auth()", "adonisjs_auth"))
        return
      end
      if group = file.groups.find { |open_at, close_at, rest| open_at < at && at < close_at && rest.matches?(AUTH_USE) }
        endpoint.add_tag(Tag.new("auth", "Protected by AdonisJS middleware.auth() on its route group", "adonisjs_auth",
          path_info.path, file.code[0, group[0]].count('\n') + 1))
        return
      end
    end
  end

  private def routes_file(path : String) : RoutesFile?
    return @files[path] if @files.has_key?(path)
    @files[path] = begin
      if content = read_file(path)
        code = Noir::CComments.strip(content, quotes: %("'`))
        offsets = [0]
        code.each_char_with_index { |char, idx| offsets << idx + 1 if char == '\n' }
        file = RoutesFile.new(code, code.chars, offsets, [] of {Int32, Int32, String})
        code.scan(GROUP_CALL) do |m|
          open = m.end(0) - 1
          close = Noir::JSLiteralScanner.find_matching_paren(file.chars, open) || next
          file.groups << {open, close, chain(file, close + 1)}
        end
        file
      end
    end
  end

  # The calls chained onto the one that ends at `from`.
  private def chain(file : RoutesFile, from : Int32) : String
    String.build do |io|
      pos = from
      while (m = file.code.match(CHAINED_CALL, pos)) && (close = Noir::JSLiteralScanner.find_matching_paren(file.chars, m.end(0) - 1))
        io << file.code[pos..close]
        pos = close + 1
      end
    end
  end
end
