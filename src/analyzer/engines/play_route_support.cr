require "../../models/endpoint"
require "../../utils/jvm_literal"

# Shared by `Analyzer::Java::Play` and `Analyzer::Scala::Play`: both read
# the same `conf/routes` grammar, so the route-line helpers (path params,
# action-signature params, include collection) are one copy here.
#
# It is a mixin because the two analyzers have no common base below
# `Analyzer`. The includer supplies `read_file_content`,
# `resolve_included_routes_file` and `request_route_param_type?` — those
# differ per language (Scala knows `RequestHeader`/`MessagesRequest` and
# resolves duplicate routes basenames by directory).
module PlayRouteSupport
  private def collect_included_routes(routes_files : Array(String), routes_by_key : Hash(Tuple(String, String), _)) : Set(String)
    included = Set(String).new

    routes_files.each do |path|
      read_file_content(path).each_line do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?("#")
        next unless include_match = stripped.match(/^->\s+[^\s]+\s+(.+)$/)

        if included_path = resolve_included_routes_file(include_match[1], routes_by_key, path)
          included << included_path
        end
      end
    end

    included
  end

  # Extract path parameters from route pattern
  private def extract_path_params(endpoint : Endpoint, route_path : String)
    # Match :param style parameters
    route_path.scan(/:(\w+)/) do |match|
      endpoint.push_param(Param.new(match[1], "", "path"))
    end

    # Match $param<regex> style parameters
    route_path.scan(/\$(\w+)<[^>]+>/) do |match|
      endpoint.push_param(Param.new(match[1], "", "path"))
    end

    # Match *param wildcard style parameters
    route_path.scan(/\*(\w+)/) do |match|
      endpoint.push_param(Param.new(match[1], "", "path"))
    end
  end

  # Extract query parameters from action signature
  # Example: controllers.Users.show(id: Long, name: String ?= "default")
  private def extract_params_from_action(endpoint : Endpoint, action : String)
    # Extract parameters from action signature
    if params_match = action.match(/\((.*)\)/)
      params_str = params_match[1]

      split_route_action_params(params_str).each do |param_def|
        param_def = param_def.strip
        next if param_def.empty?

        if route_param = route_action_param(param_def)
          param_name, param_type, default_value = route_param
          next if request_route_param_type?(param_type)
          next if endpoint.params.any? { |p| p.name == param_name }

          endpoint.push_param(Param.new(param_name, default_value, "query"))
        end
      end
    end
  end

  private def split_route_action_params(params_str : String) : Array(String)
    params = [] of String
    start = 0
    depth = 0
    in_string = false
    quote = '\0'
    escape = false

    params_str.each_char_with_index do |char, index|
      if in_string
        if escape
          escape = false
        elsif char == '\\'
          escape = true
        elsif char == quote
          in_string = false
        end
        next
      end

      case char
      when '"', '\''
        in_string = true
        quote = char
      when '(', '[', '{'
        depth += 1
      when ')', ']', '}'
        depth -= 1 if depth > 0
      when ','
        next unless depth == 0

        params << params_str[start...index].strip
        start = index + 1
      end
    end

    tail = params_str[start..]?.to_s.strip
    params << tail unless tail.empty?
    params
  end

  private def route_action_param(param_def : String) : Tuple(String, String?, String)?
    optional_default_index = top_level_operator_index(param_def, "?=")
    fixed_value_index = top_level_operator_index(param_def, "=")
    return if fixed_value_index && optional_default_index.nil?

    declaration_end = optional_default_index || param_def.size
    declaration = param_def[0...declaration_end].strip
    return if declaration.empty?

    default_value = ""
    if optional_default_index
      raw_default = param_def[(optional_default_index + 2)..].strip
      default_value = normalize_route_default_value(raw_default)
    end

    if colon = declaration.index(':')
      name = declaration[0...colon].strip
      type_name = declaration[(colon + 1)..].strip
      return if name.empty?
      return {name, type_name.empty? ? nil : type_name, default_value}
    end

    name = declaration.strip
    return unless name.match(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
    {name, nil, default_value}
  end

  private def top_level_operator_index(text : String, operator : String) : Int32?
    depth = 0
    in_string = false
    quote = '\0'
    escape = false
    i = 0
    # `text[i]`/`text[i, n]` walk the string from byte 0 on every call once
    # it holds any multi-byte UTF-8 char (no cached char->byte index), so a
    # `while i <= size - n; text[i]; ...` scan is O(n) per char, i.e. O(n^2)
    # overall on non-ASCII input. Materialize once and index the array
    # instead -- same char offsets, O(1) access.
    chars = text.chars

    while i <= chars.size - operator.size
      char = chars[i]

      if in_string
        if escape
          escape = false
        elsif char == '\\'
          escape = true
        elsif char == quote
          in_string = false
        end
        i += 1
        next
      end

      case char
      when '"', '\''
        in_string = true
        quote = char
      when '(', '[', '{'
        depth += 1
      when ')', ']', '}'
        depth -= 1 if depth > 0
      else
        # `i` is a CHAR index; comparing against the char array (rather than
        # byte-slicing `text`) avoids desyncing the match when a multi-byte
        # char precedes it.
        return i if depth == 0 && chars_match_at?(chars, i, operator)
      end
      i += 1
    end

    nil
  end

  # True when `needle` occurs in `chars` starting at `index`, char-by-char.
  private def chars_match_at?(chars : Array(Char), index : Int32, needle : String) : Bool
    needle.each_char_with_index do |ch, offset|
      return false unless chars[index + offset]? == ch
    end
    true
  end

  # A Play routes default (`name: T ?= <expr>`) is a Scala/Java expression,
  # not a value: `?= "json"` and `?= 1` are real defaults, `?= null` says
  # there is no default, and `?= List.empty` has no literal form at all.
  # See `Noir::JvmLiteral` for why the last two must not reach `Param#value`.
  private def normalize_route_default_value(raw_default : String) : String
    Noir::JvmLiteral.value_of(raw_default)
  end

  # Create an endpoint with the given path and method
  private def create_endpoint(path : String, method : String, source : String, line_number : Int32)
    details = Details.new(PathInfo.new(source, line_number))
    params = [] of Param

    Endpoint.new(path, method, params, details)
  end
end
