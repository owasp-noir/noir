require "../../../models/analyzer"
require "../../../models/endpoint"
require "json"
require "log"

# Parses GraphQL *operation documents* (`query Foo { ... }`,
# `mutation Bar { ... }`, `subscription Baz { ... }`) carried in `.graphql`
# files and emits one `/graphql` endpoint per named top-level operation.
#
# SDL schema documents are handled separately by the `graphql_sdl`
# analyzer; this analyzer deliberately reports nothing for them.
module InternalGraphqlParser
  # Keywords that introduce a top-level operation definition.
  OPERATION_KEYWORDS = {"query", "mutation", "subscription"}

  def self.parse_content(path : String, file_content : String) : Array(Endpoint)
    results = [] of Endpoint

    # Materialize into an Array(Char) for O(1) positional access. Indexing a
    # String is O(n) when it is not single-byte-optimizable, so a single
    # multi-byte char (an emoji in a description, say) would otherwise make
    # this scan quadratic.
    chars = file_content.chars
    n = chars.size
    i = 0
    line = 1
    depth = 0

    while i < n
      c = chars[i]
      case c
      when '\n'
        line += 1
        i += 1
      when '#'
        # Line comment: skip to (but not past) the newline.
        while i < n && chars[i] != '\n'
          i += 1
        end
      when '"'
        # String / block-string literal: skip it so keywords appearing as
        # prose inside a """description""" never look like operations.
        i, consumed_newlines = skip_string(chars, i, n)
        line += consumed_newlines
      when '{'
        depth += 1
        i += 1
      when '}'
        depth -= 1 if depth > 0
        i += 1
      else
        # An operation definition only ever appears at the top level
        # (brace depth 0). Requiring depth 0 rejects fields named
        # `query`/`subscription` inside a selection set and the
        # `schema { query: Root }` mapping in an SDL document.
        if depth == 0 && (i == 0 || !ident_char?(chars[i - 1])) && (keyword = keyword_at(chars, i, n))
          new_i, new_line, op_name = read_operation_name(chars, i + keyword.size, n, line)
          if op_name
            results << build_endpoint(path, keyword, op_name, line)
            line = new_line
            i = new_i
            next
          end
        end
        i += 1
      end
    end

    results
  end

  # Reads the operation name (if any) following an operation keyword and
  # validates that what follows is genuinely an operation definition — the
  # name must be followed by a variable list `(`, a directive `@`, or the
  # selection set `{`. Returns the cursor/line just past the name plus the
  # parsed name, or a nil name when this is not a named operation.
  private def self.read_operation_name(chars : Array(Char), pos : Int32, n : Int32, line : Int32) : Tuple(Int32, Int32, String?)
    cur = pos
    cur_line = line
    while cur < n && separator?(chars[cur])
      cur_line += 1 if chars[cur] == '\n'
      cur += 1
    end
    return {pos, line, nil} unless cur < n && ident_start?(chars[cur])

    name_end = cur
    while name_end < n && ident_char?(chars[name_end])
      name_end += 1
    end
    name = String.build { |s| (cur...name_end).each { |k| s << chars[k] } }

    # Peek the first significant char after the name; a real operation has a
    # variable list, a directive, or a selection set there.
    peek = name_end
    while peek < n && separator?(chars[peek])
      peek += 1
    end
    return {pos, line, nil} unless peek < n && {'(', '@', '{'}.includes?(chars[peek])

    {name_end, cur_line, name}
  end

  private def self.build_endpoint(path : String, operation_type : String, operation_name : String, line : Int32) : Endpoint
    param_value_json = {operation_type => operation_name}.to_json
    param_name = "graphql_operation_#{operation_type}_#{operation_name}"
    param = Param.new(param_name, param_value_json, "json")
    details = Details.new(PathInfo.new(path, line))
    endpoint = Endpoint.new("/graphql", "POST", details)
    endpoint.push_param(param)
    endpoint
  end

  # Skips a `"..."` or `"""..."""` literal starting at `chars[i] == '"'`.
  # Returns the cursor just past the closing quote and the number of
  # newlines consumed (so callers can keep their line counter accurate).
  private def self.skip_string(chars : Array(Char), i : Int32, n : Int32) : Tuple(Int32, Int32)
    newlines = 0
    if i + 2 < n && chars[i + 1] == '"' && chars[i + 2] == '"'
      i += 3
      while i < n
        if i + 2 < n && chars[i] == '"' && chars[i + 1] == '"' && chars[i + 2] == '"'
          return {i + 3, newlines}
        end
        newlines += 1 if chars[i] == '\n'
        i += 1
      end
      {i, newlines}
    else
      i += 1
      while i < n
        ch = chars[i]
        if ch == '\\' && i + 1 < n
          i += 2
        elsif ch == '"'
          return {i + 1, newlines}
        else
          newlines += 1 if ch == '\n'
          i += 1
        end
      end
      {i, newlines}
    end
  end

  private def self.keyword_at(chars : Array(Char), i : Int32, n : Int32) : String?
    OPERATION_KEYWORDS.each do |kw|
      ksize = kw.size
      next if i + ksize > n
      matched = true
      kw.each_char_with_index do |kc, off|
        if chars[i + off] != kc
          matched = false
          break
        end
      end
      next unless matched
      after = i + ksize
      return kw if after >= n || !ident_char?(chars[after])
    end
    nil
  end

  private def self.ident_char?(c : Char) : Bool
    c.ascii_alphanumeric? || c == '_'
  end

  private def self.ident_start?(c : Char) : Bool
    c.ascii_letter? || c == '_'
  end

  private def self.separator?(c : Char) : Bool
    c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == ','
  end
end

FileAnalyzer.add_hook(->(path : String, _url : String) : Array(Endpoint) {
  # Operation documents ship with either extension; `.graphqls` is
  # SDL-only by convention and is left to the graphql_sdl analyzer.
  return [] of Endpoint unless path.ends_with?(".graphql") || path.ends_with?(".gql")

  begin
    file_content = File.read(path, encoding: "utf-8", invalid: :skip)
  rescue ex
    Log.debug { "GraphQL Analyzer: Error reading file #{path}: #{ex.message} (#{ex.class})" }
    return [] of Endpoint # Return empty if read fails
  end

  InternalGraphqlParser.parse_content(path, file_content)
})
