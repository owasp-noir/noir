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
  # are the file's), each line's byte offset, and every group call's
  # `{open paren, close paren, chain after it}`.
  private record RoutesFile, code : String, offsets : Array(Int32), groups : Array({Int32, Int32, String})

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
      line_end = line < file.offsets.size ? file.offsets[line] : file.code.bytesize
      # The first call on this line only. Offsets are bytes, so a multibyte
      # argument between the parens still leaves the chained `.use` attached.
      if (open = file.code.byte_index('('.ord, at)) && open < line_end &&
         (close = Noir::JSLiteralScanner.find_matching_paren_at_byte(file.code, open)) &&
         chain(file, close + 1).matches?(AUTH_USE)
        endpoint.add_tag(Tag.new("auth", "Protected by AdonisJS middleware.auth()", "adonisjs_auth"))
        return
      end
      if group = file.groups.find { |open_at, close_at, rest| open_at < at && at < close_at && rest.matches?(AUTH_USE) }
        endpoint.add_tag(Tag.new("auth", "Protected by AdonisJS middleware.auth() on its route group", "adonisjs_auth",
          path_info.path, file.code.byte_slice(0, group[0]).count('\n') + 1))
        return
      end
    end
  end

  private def routes_file(path : String) : RoutesFile?
    return @files[path] if @files.has_key?(path)
    @files[path] = begin
      if content = read_file(path)
        code = Noir::CComments.strip(content, quotes: %("'`))
        offsets = [] of Int32
        byte_at = 0
        code.each_line(chomp: false) do |line|
          offsets << byte_at
          byte_at += line.bytesize
        end
        file = RoutesFile.new(code, offsets, [] of {Int32, Int32, String})
        code.scan(GROUP_CALL) do |m|
          open = m.byte_end(0) - 1
          close = Noir::JSLiteralScanner.find_matching_paren_at_byte(code, open) || next
          file.groups << {open, close, chain(file, close + 1)}
        end
        file
      end
    end
  end

  # The calls chained onto the one that ends at byte `from`.
  # `String#match` takes a character index; the paren walker takes bytes.
  private def chain(file : RoutesFile, from : Int32) : String
    String.build do |io|
      pos = from
      while (char_pos = file.code.byte_index_to_char_index(pos)) &&
            (m = file.code.match(CHAINED_CALL, char_pos)) &&
            (close = Noir::JSLiteralScanner.find_matching_paren_at_byte(file.code, m.byte_end(0) - 1))
        io << file.code.byte_slice(pos, close - pos + 1)
        pos = close + 1
      end
    end
  end
end
