require "../models/endpoint"

module Noir::ClojureCalleeExtractor
  extend self

  alias Entry = Tuple(String, String, Int32)

  RESERVED = Set{
    "def", "defn", "defmacro", "fn", "let", "letfn", "if", "if-not",
    "when", "when-not", "when-let", "when-first", "cond", "condp",
    "case", "do", "doseq", "dotimes", "for", "loop", "recur",
    "try", "catch", "finally", "throw", "quote", "var", "new",
    "set!", "and", "or", "not", "->", "->>", "as->", "cond->",
    "cond->>", "some->", "some->>", "doto", ".", "..", "comment",
    "str", "println", "print", "prn", "list", "vector", "hash-map",
    "map", "filter", "reduce", "partial", "comp", "identity",
  }

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry
    scan_forms(body, 0, body.bytesize, file_path, start_line, entries)
    dedup_entries(entries)
  end

  def attach_to(endpoint : Endpoint, callees : Array(Entry))
    callees.each do |name, path, line|
      endpoint.push_callee(Callee.new(name, path: path, line: line))
    end
  end

  private def scan_forms(source : String,
                         start_index : Int32,
                         end_index : Int32,
                         file_path : String,
                         start_line : Int32,
                         entries : Array(Entry))
    i = start_index
    while i < end_index
      case source.byte_at(i).unsafe_chr
      when ';'
        i = skip_comment(source, i, end_index)
      when '"'
        i = skip_string(source, i, end_index) + 1
      when '\'', '`'
        i = skip_quoted_form(source, i + 1, end_index)
      when '#'
        next_char = i + 1 < end_index ? source.byte_at(i + 1).unsafe_chr : '\0'
        if next_char == '_'
          i = skip_quoted_form(source, i + 2, end_index)
        else
          i += 1
        end
      when '('
        form_end = find_matching_delimiter(source, i, '(', ')', end_index)
        break if form_end <= i

        symbol_start = skip_ws_and_comments(source, i + 1, form_end)
        symbol, after_symbol = read_symbol(source, symbol_start, form_end)
        unless skip_callee?(symbol)
          entries << {symbol, file_path, line_number_for(source, i, start_line)}
        end

        scan_forms(source, after_symbol, form_end, file_path, start_line, entries) unless quoted_form?(symbol)
        i = form_end + 1
      else
        i += 1
      end
    end
  end

  private def quoted_form?(symbol : String) : Bool
    reserved_symbol?(symbol, "quote")
  end

  private def skip_callee?(symbol : String) : Bool
    return true if symbol.empty?
    return true if symbol.starts_with?(':')

    reserved_symbol?(symbol)
  end

  private def reserved_symbol?(symbol : String, expected : String? = nil) : Bool
    if symbol.includes?('/')
      return false unless symbol.starts_with?("clojure.core/")

      base = base_symbol(symbol)
    else
      base = symbol
    end

    if expected
      base == expected
    else
      RESERVED.includes?(base)
    end
  end

  private def base_symbol(symbol : String) : String
    if index = symbol.rindex('/')
      symbol[(index + 1)..]
    else
      symbol
    end
  end

  private def skip_quoted_form(source : String, index : Int32, limit : Int32) : Int32
    i = skip_ws_and_comments(source, index, limit)
    return i if i >= limit

    case source.byte_at(i).unsafe_chr
    when '('
      find_matching_delimiter(source, i, '(', ')', limit) + 1
    when '['
      find_matching_delimiter(source, i, '[', ']', limit) + 1
    when '{'
      find_matching_delimiter(source, i, '{', '}', limit) + 1
    when '"'
      skip_string(source, i, limit) + 1
    else
      _, after_symbol = read_symbol(source, i, limit)
      after_symbol
    end
  end

  private def read_symbol(source : String, index : Int32, limit : Int32) : Tuple(String, Int32)
    i = index
    while i < limit
      char = source.byte_at(i).unsafe_chr
      break if whitespace?(char) || {'(', ')', '[', ']', '{', '}', '"', ';'}.includes?(char)

      i += 1
    end

    {source[index...i], i}
  end

  private def skip_ws_and_comments(source : String, index : Int32, limit : Int32) : Int32
    i = index
    while i < limit
      char = source.byte_at(i).unsafe_chr
      if whitespace?(char)
        i += 1
      elsif char == ';'
        i = skip_comment(source, i, limit)
      else
        break
      end
    end
    i
  end

  private def skip_comment(source : String, index : Int32, limit : Int32) : Int32
    i = index
    while i < limit && source.byte_at(i).unsafe_chr != '\n'
      i += 1
    end
    i
  end

  private def skip_string(source : String, index : Int32, limit : Int32) : Int32
    i = index + 1
    escaping = false

    while i < limit
      char = source.byte_at(i).unsafe_chr
      if escaping
        escaping = false
      elsif char == '\\'
        escaping = true
      elsif char == '"'
        return i
      end
      i += 1
    end

    limit - 1
  end

  private def find_matching_delimiter(source : String, index : Int32, open_char : Char, close_char : Char, limit : Int32) : Int32
    depth = 0
    i = index

    while i < limit
      char = source.byte_at(i).unsafe_chr
      case char
      when ';'
        i = skip_comment(source, i, limit)
      when '"'
        i = skip_string(source, i, limit)
      when open_char
        depth += 1
      when close_char
        depth -= 1
        return i if depth == 0
      end
      i += 1
    end

    index
  end

  private def line_number_for(source : String, index : Int32, start_line : Int32) : Int32
    start_line + source.to_slice[0, index].count('\n'.ord.to_u8)
  end

  private def whitespace?(char : Char) : Bool
    char.whitespace?
  end

  private def dedup_entries(entries : Array(Entry)) : Array(Entry)
    seen = Set(Entry).new
    entries.select { |entry| seen.add?(entry) }
  end
end
