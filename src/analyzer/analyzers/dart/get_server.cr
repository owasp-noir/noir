require "../../../models/analyzer"
require "../../../miniparsers/dart_callee_extractor"
require "./dart_helper"

module Analyzer::Dart
  # get_server (`package:get_server/get_server.dart`) is a GetX-style Dart
  # server framework. Routes are declared as a list of `GetPage` entries
  # passed to `GetServer(getPages: ...)`:
  #
  #   GetServer(getPages: AppPages.routes);
  #
  #   class AppPages {
  #     static final routes = [
  #       GetPage(name: Routes.HOME, page: () => HomePage(), method: Method.get),
  #       GetPage(name: Routes.USER, page: () => UserPage()),       // any verb
  #       GetPage(name: '/upload', page: () => UploadPage(), method: Method.post),
  #     ];
  #   }
  #
  #   class Routes {
  #     static const HOME = '/';
  #     static const USER = '/user/:name';
  #   }
  #
  # `name:` is either a string literal or a reference to a `static const`
  # path (often declared in a separate `part` file), so path constants are
  # collected project-wide and resolved by name. `method:` maps to a verb;
  # when omitted it defaults to `Method.dynamic`, which matches every HTTP
  # method. `Method.ws` is a WebSocket upgrade (surfaced as `GET`). Path
  # captures use the Express-style `:id` syntax → `{id}`.
  class GetServer < Analyzer
    METHOD_MAP = {
      "get"     => "GET",
      "post"    => "POST",
      "put"     => "PUT",
      "delete"  => "DELETE",
      "patch"   => "PATCH",
      "options" => "OPTIONS",
      "head"    => "HEAD",
    }

    ALL_VERBS = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    alias RawPage = NamedTuple(
      name_arg: String,
      method_arg: String?,
      page_arg: String?,
      file: String,
      line: Int32)

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      const_map = {} of String => String
      raw_pages = [] of RawPage
      mutex = Mutex.new

      begin
        files = get_files_by_extension(".dart")

        parallel_analyze(files) do |path|
          next unless path.ends_with?(".dart")
          next if Helper.test_path?(path, base_paths)

          content = begin
            read_file_content(path)
          rescue e
            logger.debug "Error reading #{path}: #{e.message}"
            next
          end

          cleaned = Helper.strip_comments(content)
          local_consts = collect_constants(cleaned)
          local_pages = collect_pages(cleaned, content, path)
          next if local_consts.empty? && local_pages.empty?

          mutex.synchronize do
            local_consts.each { |k, v| const_map[k] = v }
            raw_pages.concat(local_pages)
          end
        end
      rescue e
        logger.debug e
      end

      # A path constant can interpolate another (`const TURN_OFF =
      # '$TUYA/turn_off'`); resolve those references now that every
      # constant has been collected project-wide.
      resolve_const_interpolations(const_map)

      assemble(raw_pages, const_map, include_callee)
    end

    INTERP_BRACE = /\$\{([^}]+)\}/
    INTERP_BARE  = /\$([A-Za-z_]\w*)/

    # Substitute `$IDENT` / `${expr}` interpolations with the referenced
    # path constant's value (by bare constant name). Unknown references are
    # left untouched.
    private def resolve_interpolation(value : String, const_map : Hash(String, String)) : String
      result = value.gsub(INTERP_BRACE) do
        key = $~[1].strip.split('.').last
        const_map[key]? || $~[0]
      end
      result.gsub(INTERP_BARE) do
        const_map[$~[1]]? || $~[0]
      end
    end

    # Resolve constant-to-constant interpolation to a fixpoint (a few
    # passes settle chains like `B = '$A/x'`, `C = '$B/y'`). Capped so an
    # unresolved/cyclic reference can't loop forever.
    private def resolve_const_interpolations(const_map : Hash(String, String))
      5.times do
        changed = false
        const_map.each do |key, value|
          next unless value.includes?('$')
          resolved = resolve_interpolation(value, const_map)
          if resolved != value
            const_map[key] = resolved
            changed = true
          end
        end
        break unless changed
      end
    end

    # `static const NAME = '/path'` (and plain `const NAME = '/path'`)
    # path constants, keyed by the bare constant name. Only string-literal
    # values are kept — those are the route paths referenced by `GetPage`.
    CONST_REGEX = /\bconst\s+(?:String\s+)?([A-Za-z_]\w*)\s*=\s*(['"])/

    private def collect_constants(cleaned : String) : Hash(String, String)
      consts = {} of String => String
      cleaned.scan(CONST_REGEX) do |m|
        name = m[1]
        quote_pos = m.end(0).try &.- 1
        next unless quote_pos
        literal = Helper.extract_string_literal(cleaned[quote_pos..])
        next unless literal
        consts[name] = literal
      end
      consts
    end

    GET_PAGE_REGEX = /\bGetPage\s*\(/

    private def collect_pages(cleaned : String, content : String, path : String) : Array(RawPage)
      pages = [] of RawPage
      cleaned.scan(GET_PAGE_REGEX) do |m|
        match_begin = m.begin(0)
        open_paren = m.end(0).try &.- 1
        next unless match_begin && open_paren
        close_paren = find_matching_paren(cleaned, open_paren)
        next unless close_paren

        args = named_args(cleaned[(open_paren + 1)...close_paren])
        name_arg = args["name"]?
        next unless name_arg

        line = line_for_offset(content, match_begin)
        pages << {
          name_arg:   name_arg,
          method_arg: args["method"]?,
          page_arg:   args["page"]?,
          file:       path,
          line:       line,
        }
      end
      pages
    end

    private def assemble(raw_pages : Array(RawPage),
                         const_map : Hash(String, String),
                         include_callee : Bool) : Array(Endpoint)
      result = [] of Endpoint
      seen = Set({String, String, String}).new # (verb, url, file)

      raw_pages.each do |page|
        url = resolve_name(page[:name_arg], const_map)
        next unless url

        verbs = resolve_verbs(page[:method_arg])
        callees = include_callee ? page_callees(page[:page_arg], page[:file], page[:line]) : [] of Noir::DartCalleeExtractor::Entry

        verbs.each do |verb|
          next unless seen.add?({verb, url, page[:file]})
          result << build_endpoint(url, verb, page[:file], page[:line], callees)
        end
      end

      result
    end

    private def resolve_name(arg : String, const_map : Hash(String, String)) : String?
      stripped = arg.strip
      if literal = Helper.extract_string_literal(stripped)
        # `name: '$TUYA/turn_off'` — an interpolated literal resolves
        # against the collected path constants.
        return normalize_path(resolve_interpolation(literal, const_map))
      end
      # Reference to a path constant (`Routes.HOME` / `HOME`): resolve by
      # the bare constant name.
      return unless stripped.matches?(/\A[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\z/)
      key = stripped.split('.').last
      value = const_map[key]?
      value ? normalize_path(value) : nil
    end

    private def resolve_verbs(method_arg : String?) : Array(String)
      return ALL_VERBS unless method_arg
      m = method_arg.match(/Method\s*\.\s*([a-zA-Z]+)/)
      return ALL_VERBS unless m
      verb = m[1].downcase
      case verb
      when "dynamic"
        ALL_VERBS
      when "ws"
        ["GET"] # WebSocket upgrade handshake is a GET.
      else
        mapped = METHOD_MAP[verb]?
        mapped ? [mapped] : ALL_VERBS
      end
    end

    private def page_callees(page_arg : String?, path : String, line : Int32) : Array(Noir::DartCalleeExtractor::Entry)
      return [] of Noir::DartCalleeExtractor::Entry unless page_arg
      Noir::DartCalleeExtractor.callees_for_body(page_arg, path, line)
    end

    # Ensure a leading slash and translate Express-style `:id` captures
    # into `{id}` path params.
    private def normalize_path(path : String) : String
      base = path.starts_with?('/') ? path : "/#{path}"
      base.gsub(/:([A-Za-z_]\w*)/) { "{#{$~[1]}}" }
    end

    private def build_endpoint(url : String,
                               verb : String,
                               path : String,
                               line : Int32,
                               callees : Array(Noir::DartCalleeExtractor::Entry)) : Endpoint
      endpoint = Endpoint.new(url, verb)
      endpoint.details = Details.new(PathInfo.new(path, line))
      url.scan(/\{(\w+)\}/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
      Noir::DartCalleeExtractor.attach_to(endpoint, callees)
      endpoint
    end

    # ---------- source-string utilities ----------

    # Split a call's argument list into a `name: value` map at top level.
    private def named_args(text : String) : Hash(String, String)
      result = {} of String => String
      split_top_level_args(text).each do |raw|
        arg = raw.strip
        next if arg.empty?
        colon = top_level_colon(arg)
        next unless colon
        key = arg[0...colon].strip
        next unless key.matches?(/\A[A-Za-z_]\w*\z/)
        result[key] = arg[(colon + 1)..].strip
      end
      result
    end

    # Index of the first `:` outside any bracket/paren/string — the
    # separator of a named argument.
    private def top_level_colon(text : String) : Int32?
      depth = 0
      i = 0
      in_string = false
      string_quote = '\0'
      while i < text.size
        c = text[i]
        if in_string
          if c == '\\' && i + 1 < text.size
            i += 2
            next
          end
          in_string = false if c == string_quote
          i += 1
          next
        end
        case c
        when '"', '\''
          in_string = true
          string_quote = c
        when '(', '{', '[', '<'
          depth += 1
        when ')', '}', ']', '>'
          depth -= 1 if depth > 0
        when ':'
          return i if depth == 0
        else
          # ignore
        end
        i += 1
      end
      nil
    end

    private def find_matching_paren(text : String, open_idx : Int32) : Int32?
      depth = 0
      i = open_idx
      in_string = false
      string_quote = '\0'

      while i < text.size
        c = text[i]
        if in_string
          if c == '\\' && i + 1 < text.size
            i += 2
            next
          end
          in_string = false if c == string_quote
          i += 1
          next
        end

        case c
        when '"', '\''
          in_string = true
          string_quote = c
        when '('
          depth += 1
        when ')'
          depth -= 1
          return i if depth == 0
        else
          # ignore
        end
        i += 1
      end

      nil
    end

    private def split_top_level_args(text : String) : Array(String)
      result = [] of String
      depth_paren = 0
      depth_brace = 0
      depth_bracket = 0
      depth_angle = 0
      start = 0
      i = 0
      in_string = false
      string_quote = '\0'

      while i < text.size
        c = text[i]
        if in_string
          if c == '\\' && i + 1 < text.size
            i += 2
            next
          end
          in_string = false if c == string_quote
          i += 1
          next
        end

        case c
        when '"', '\''
          in_string = true
          string_quote = c
        when '('
          depth_paren += 1
        when ')'
          depth_paren -= 1 if depth_paren > 0
        when '{'
          depth_brace += 1
        when '}'
          depth_brace -= 1 if depth_brace > 0
        when '['
          depth_bracket += 1
        when ']'
          depth_bracket -= 1 if depth_bracket > 0
        when '<'
          depth_angle += 1
        when '>'
          depth_angle -= 1 if depth_angle > 0
        when ','
          if depth_paren == 0 && depth_brace == 0 && depth_bracket == 0 && depth_angle == 0
            result << text[start...i]
            start = i + 1
          end
        else
          # ignore
        end
        i += 1
      end
      result << text[start..] if start <= text.size
      result
    end

    private def line_for_offset(content : String, offset : Int32) : Int32
      return 1 if offset <= 0
      limit = offset > content.size ? content.size : offset
      count = 1
      i = 0
      while i < limit
        count += 1 if content[i] == '\n'
        i += 1
      end
      count
    end
  end
end
