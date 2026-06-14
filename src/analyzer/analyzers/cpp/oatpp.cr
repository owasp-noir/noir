require "../../../models/analyzer"
require "../../../miniparsers/cpp_callee_extractor"

module Analyzer::Cpp
  # oat++ (oatpp) — routes are declared inside an `ApiController` subclass with
  # code-gen macros:
  #
  #   ENDPOINT("GET", "users/{userId}", getUserById, PATH(Int32, userId)) { ... }
  #   ENDPOINT_ASYNC("GET", "room/{roomId}", ChatHTML) { ...Action class... }
  #
  # The verb and path are the first two macro arguments; the remaining
  # arguments of a sync ENDPOINT are typed parameter declarations
  # (PATH/QUERY/HEADER/BODY_DTO/…). Async endpoints declare their parameters
  # inside the generated coroutine class, so only the path placeholders are
  # mined from those.
  class Oatpp < Analyzer
    CPP_EXTENSIONS = [".cpp", ".cc", ".cxx", ".h", ".hpp", ".hxx"]

    HTTP_VERBS = Set{"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"}

    ENDPOINT_REGEX       = /\bENDPOINT\s*\(/
    ENDPOINT_ASYNC_REGEX = /\bENDPOINT_ASYNC\s*\(/
    PATH_PARAM_REGEX     = /\{([^{}\/]+)\}/

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      begin
        locator = CodeLocator.instance
        files = CPP_EXTENSIONS.flat_map { |ext| locator.files_by_extension(ext) }

        parallel_analyze(files) do |path|
          next if File.directory?(path)
          next unless File.exists?(path)
          analyze_file(path, include_callee)
        end
      rescue e
        logger.debug "oatpp analyzer failed: #{e.message}"
      end

      result
    end

    private def analyze_file(path : String, include_callee : Bool)
      source = read_file_content(path)
      return unless source.includes?("oatpp") || source.includes?("ApiController")
      return unless source.includes?("ENDPOINT(") || source.includes?("ENDPOINT_ASYNC(")

      source = Noir::CppCalleeExtractor.strip_comments(source)

      each_macro(source, ENDPOINT_REGEX) do |args, close_paren, call_start|
        emit_endpoint(path, source, args, close_paren, call_start, include_callee, async: false)
      end

      each_macro(source, ENDPOINT_ASYNC_REGEX) do |args, close_paren, call_start|
        emit_endpoint(path, source, args, close_paren, call_start, include_callee, async: true)
      end
    end

    private def emit_endpoint(path : String, source : String, args : Array(String), close_paren : Int32, call_start : Int32, include_callee : Bool, async : Bool)
      verb = parse_verb(args[0]?)
      return unless verb
      raw_path = unquote(args[1]?)
      return unless raw_path

      clean_path, path_params = normalize_path(raw_path)
      line_number = Noir::CppCalleeExtractor.line_number_for(source, call_start)
      details = Details.new(PathInfo.new(path, line_number))
      endpoint = Endpoint.new(clean_path, verb, path_params.dup, details)

      # Sync ENDPOINT: args[3..] are typed parameter declarations. Async
      # endpoints carry no inline declarations.
      unless async
        args[3..]?.try &.each do |decl|
          if param = parse_param_decl(decl)
            push_unique(endpoint, param)
          end
        end
      end

      if include_callee
        if block = Noir::CppCalleeExtractor.extract_block_after(source, close_paren)
          body, start_line = block
          Noir::CppCalleeExtractor.attach_to(endpoint, Noir::CppCalleeExtractor.callees_for_body(body, path, start_line))
        end
      end

      result << endpoint
    end

    private def each_macro(source : String, regex : Regex, &block : Array(String), Int32, Int32 ->)
      source.scan(regex) do |match|
        call_start = source.char_index_to_byte_index(match.begin(0) || 0) || 0
        open_paren = Noir::CppCalleeExtractor.find_next_code_char(source, '(', call_start)
        next unless open_paren
        close_paren = Noir::CppCalleeExtractor.find_matching_delimiter(source, open_paren, '(', ')')
        next unless close_paren

        args = split_top_level_args(source.byte_slice(open_paren + 1, close_paren - open_paren - 1))
        block.call(args, close_paren, call_start)
      end
    end

    private def parse_verb(raw : String?) : String?
      verb = unquote(raw)
      return unless verb
      verb = verb.upcase
      HTTP_VERBS.includes?(verb) ? verb : nil
    end

    private def unquote(raw : String?) : String?
      return unless raw
      s = raw.strip
      return unless s.size >= 2 && s.starts_with?('"') && s.ends_with?('"')
      s[1...-1]
    end

    private def normalize_path(raw : String) : Tuple(String, Array(Param))
      params = [] of Param
      raw.scan(PATH_PARAM_REGEX) { |m| params << Param.new(m[1], "", "path") }
      {raw, params}
    end

    # Parses a single oatpp parameter macro into a Param:
    #   PATH(Int32, userId)              → path  userId
    #   QUERY(String, name)              → query name
    #   QUERY(String, n, "realName")     → query realName  (the 3rd-arg override)
    #   HEADER(String, h, "X-Token")     → header X-Token
    #   BODY_DTO(Object<Dto>, dto)       → json  body
    #   BODY_STRING(body)                → body  body
    private def parse_param_decl(decl : String) : Param?
      stripped = decl.strip
      open = stripped.index('(')
      return unless open
      macro_name = stripped[0...open].strip
      close = stripped.rindex(')')
      return unless close && close > open
      inner = split_top_level_args(stripped[(open + 1)...close])

      case macro_name
      when "PATH"
        name = inner[1]?.try(&.strip)
        name && !name.empty? ? Param.new(name, "", "path") : nil
      when "QUERY"
        name = string_literal(inner[2]?) || inner[1]?.try(&.strip)
        name && !name.empty? ? Param.new(name, "", "query") : nil
      when "HEADER"
        name = string_literal(inner[2]?) || inner[1]?.try(&.strip)
        name && !name.empty? ? Param.new(name, "", "header") : nil
      when "BODY_DTO"
        Param.new("body", "", "json")
      when "BODY_STRING"
        Param.new("body", "", "body")
      end
    end

    private def string_literal(raw : String?) : String?
      return unless raw
      s = raw.strip
      return unless s.size >= 2 && s.starts_with?('"') && s.ends_with?('"')
      s[1...-1]
    end

    private def push_unique(endpoint : Endpoint, param : Param)
      return if param.name.empty?
      return if endpoint.params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      endpoint.push_param(param)
    end

    private def split_top_level_args(raw : String) : Array(String)
      args = [] of String
      current = String::Builder.new
      paren = 0
      brace = 0
      bracket = 0
      in_string = false
      escaped = false

      raw.each_char do |char|
        if in_string
          current << char
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        case char
        when '"' then in_string = true
        when '(' then paren += 1
        when ')' then paren -= 1 if paren > 0
        when '{' then brace += 1
        when '}' then brace -= 1 if brace > 0
        when '[' then bracket += 1
        when ']' then bracket -= 1 if bracket > 0
        when ','
          if paren == 0 && brace == 0 && bracket == 0
            args << current.to_s.strip
            current = String::Builder.new
            next
          end
        end

        current << char
      end

      tail = current.to_s.strip
      args << tail unless tail.empty?
      args
    end
  end
end
