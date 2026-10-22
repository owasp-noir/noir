require "../models/endpoint"
require "json"

module Noir
  # Parses GraphQL *operation documents* (`query Foo { ... }`,
  # `mutation Bar { ... }`, `subscription Baz { ... }`) carried in `.graphql`
  # / `.gql` files and emits one `/graphql` endpoint per named top-level
  # operation.
  #
  # SDL schema documents are handled separately by the `graphql_sdl`
  # analyzer; this parser deliberately reports nothing for them.
  #
  # The scan is exposed twice: `parse_content` builds the endpoints, and
  # `operation_document?` stops at the first operation. The detector uses the
  # predicate, so "the detector claims this file" and "the analyzer produces
  # something from it" are the same test rather than two that can drift.
  module GraphqlOperationParser
    extend self

    DEFAULT_GRAPHQL_PATH = "/graphql"

    # Keywords that introduce a top-level operation definition.
    OPERATION_KEYWORDS = {"query", "mutation", "subscription"}

    def parse_content(path : String, file_content : String) : Array(Endpoint)
      results = [] of Endpoint
      each_operation(file_content) do |keyword, name, line|
        results << build_endpoint(path, keyword, name, line)
      end
      results
    end

    # True as soon as one named top-level operation is found. Same walk as
    # `parse_content`, without building any endpoint.
    def operation_document?(file_content : String) : Bool
      each_operation(file_content) { return true }
      false
    end

    # Yields `{keyword, operation_name, line}` for every named top-level
    # operation definition in `file_content`.
    private def each_operation(file_content : String, & : String, String, Int32 -> _) : Nil
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
              yield keyword, op_name, line
              line = new_line
              i = new_i
              next
            end
          end
          i += 1
        end
      end
    end

    # Reads the operation name (if any) following an operation keyword and
    # validates that what follows is genuinely an operation definition — the
    # name must be followed by a variable list `(`, a directive `@`, or the
    # selection set `{`. Returns the cursor/line just past the name plus the
    # parsed name, or a nil name when this is not a named operation.
    private def read_operation_name(chars : Array(Char), pos : Int32, n : Int32, line : Int32) : Tuple(Int32, Int32, String?)
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

    private def build_endpoint(path : String, operation_type : String, operation_name : String, line : Int32) : Endpoint
      param_value_json = {operation_type => operation_name}.to_json
      param_name = "graphql_operation_#{operation_type}_#{operation_name}"
      param = Param.new(param_name, param_value_json, "json")
      details = Details.new(PathInfo.new(path, line))
      endpoint = Endpoint.new(DEFAULT_GRAPHQL_PATH, "POST", details)
      endpoint.push_param(param)
      endpoint
    end

    # Skips a `"..."` or `"""..."""` literal starting at `chars[i] == '"'`.
    # Returns the cursor just past the closing quote and the number of
    # newlines consumed (so callers can keep their line counter accurate).
    private def skip_string(chars : Array(Char), i : Int32, n : Int32) : Tuple(Int32, Int32)
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

    private def keyword_at(chars : Array(Char), i : Int32, n : Int32) : String?
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

    private def ident_char?(c : Char) : Bool
      c.ascii_alphanumeric? || c == '_'
    end

    private def ident_start?(c : Char) : Bool
      c.ascii_letter? || c == '_'
    end

    private def separator?(c : Char) : Bool
      c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == ','
    end
  end
end
