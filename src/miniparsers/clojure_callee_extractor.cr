require "../models/endpoint"
require "./callee_extractor_base"

module Noir::ClojureCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  RESERVED = Set{
    "def", "defn", "defmacro", "fn", "let", "letfn", "if", "if-not",
    "if-let", "if-some", "when", "when-not", "when-let", "when-some",
    "when-first", "while", "cond", "condp",
    "case", "do", "doseq", "dotimes", "for", "loop", "recur",
    "try", "catch", "finally", "throw", "quote", "var", "new",
    "set!", "and", "or", "not", "->", "->>", "as->", "cond->",
    "cond->>", "some->", "some->>", "doto", ".", "..", "comment",
    "str", "println", "print", "prn", "list", "vector", "hash-map",
    "map", "filter", "reduce", "partial", "comp", "identity",
    # Arithmetic / comparison operators are clojure.core primitives, not
    # meaningful handler callees — they only add noise to AI context.
    "+", "-", "*", "/", "=", "==", "<", ">", "<=", ">=", "not=",
    # Collection plumbing (clojure.core). These shuffle data — building
    # interceptor chains, assembling response maps — rather than expressing
    # handler logic, so they are noise in AI context.
    "conj", "conj!", "into", "merge", "merge-with", "concat", "cons",
    "assoc", "assoc!", "assoc-in", "dissoc", "update", "update-in",
    "get", "get-in", "select-keys", "vec", "set", "seq", "keys", "vals",
  }

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry
    scan_forms(body, 0, body.bytesize, file_path, start_line, entries)
    dedup_entries(entries)
  end

  def function_callees(source : String, file_path : String) : Hash(String, Array(Entry))
    result = Hash(String, Array(Entry)).new
    scan_function_definitions(source, 0, source.bytesize, file_path, result)
    result
  end

  private def scan_function_definitions(source : String,
                                        start_index : Int32,
                                        end_index : Int32,
                                        file_path : String,
                                        result : Hash(String, Array(Entry)))
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
        base = base_symbol(symbol)
        if base == "defn" || base == "defn-"
          collect_defn_callees(source, after_symbol, form_end, file_path, result)
        else
          scan_function_definitions(source, after_symbol, form_end, file_path, result) unless quoted_form?(symbol)
        end

        i = form_end + 1
      else
        i += 1
      end
    end
  end

  private def collect_defn_callees(source : String,
                                   index : Int32,
                                   form_end : Int32,
                                   file_path : String,
                                   result : Hash(String, Array(Entry)))
    name_start = skip_metadata(source, index, form_end)
    name, after_name = read_symbol(source, name_start, form_end)
    return if name.empty?

    body_start = defn_body_start(source, after_name, form_end)
    return if body_start >= form_end

    body = source.byte_slice(body_start, form_end - body_start)
    start_line = line_number_for(source, body_start, 1)
    result[name] = callees_for_body(body, file_path, start_line)
  end

  private def skip_metadata(source : String, index : Int32, limit : Int32) : Int32
    i = skip_ws_and_comments(source, index, limit)
    while i < limit && source.byte_at(i).unsafe_chr == '^'
      i = skip_metadata_value(source, i + 1, limit)
      i = skip_ws_and_comments(source, i, limit)
    end
    i
  end

  private def skip_metadata_value(source : String, index : Int32, limit : Int32) : Int32
    i = skip_ws_and_comments(source, index, limit)
    return i if i >= limit

    case source.byte_at(i).unsafe_chr
    when '"'
      skip_string(source, i, limit) + 1
    when '{'
      end_index = find_matching_delimiter(source, i, '{', '}', limit)
      end_index > i ? end_index + 1 : limit
    else
      _, after_symbol = read_symbol(source, i, limit)
      after_symbol
    end
  end

  private def defn_body_start(source : String, index : Int32, limit : Int32) : Int32
    i = skip_ws_and_comments(source, index, limit)

    # Optional docstring.
    if i < limit && source.byte_at(i).unsafe_chr == '"'
      doc_end = skip_string(source, i, limit)
      i = skip_ws_and_comments(source, doc_end + 1, limit)
    end

    # Optional attr map.
    if i < limit && source.byte_at(i).unsafe_chr == '{'
      map_end = find_matching_delimiter(source, i, '{', '}', limit)
      i = skip_ws_and_comments(source, map_end + 1, limit) if map_end > i
    end

    # Single arity: `(defn name [args] body...)`.
    if i < limit && source.byte_at(i).unsafe_chr == '['
      args_end = find_matching_delimiter(source, i, '[', ']', limit)
      return skip_ws_and_comments(source, args_end + 1, limit) if args_end > i
    end

    # Multi arity: `(defn name ([args] body...) ([args] body...))`.
    i
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
      when '`'
        # Syntax-quote of a bare symbol (`` `ns/handler ``) is the idiomatic
        # Pedestal tabular-route handler reference — capture it. Syntax-quoted
        # collections/strings stay code templates and are skipped.
        i = scan_quoted_symbol(source, i, end_index, file_path, start_line, entries)
      when '\''
        i = skip_quoted_form(source, i + 1, end_index)
      when '#'
        next_char = i + 1 < end_index ? source.byte_at(i + 1).unsafe_chr : '\0'
        if next_char == '_'
          i = skip_quoted_form(source, i + 2, end_index)
        elsif next_char == '\''
          # Var-quote `#'handler` resolves a var — a deliberate function
          # reference (the idiomatic Ring/Compojure handler form, e.g.
          # `(wrap #'user-ctl/default)`). Record the var'd symbol as a callee
          # rather than skipping it like an ordinary quote.
          symbol, after_symbol = read_symbol(source, i + 2, end_index)
          unless skip_callee?(symbol)
            entries << {symbol, file_path, line_number_for(source, i, start_line)}
          end
          i = after_symbol
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
    # `/` is the bare division operator, not a namespaced symbol — the `/`
    # it contains is the whole name. Treat it as an ordinary base symbol so
    # it can match the RESERVED entry rather than being read as a namespace.
    if symbol.includes?('/') && symbol != "/"
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

  # Handle a syntax-quote `` ` `` at `index`. When it quotes a bare symbol
  # (a route-handler reference) the symbol is recorded as a callee; quoted
  # collections/strings are skipped as code templates. Returns the index past
  # the quoted form.
  private def scan_quoted_symbol(source : String,
                                 index : Int32,
                                 limit : Int32,
                                 file_path : String,
                                 start_line : Int32,
                                 entries : Array(Entry)) : Int32
    i = skip_ws_and_comments(source, index + 1, limit)
    return i if i >= limit

    case source.byte_at(i).unsafe_chr
    when '(', '[', '{', '"', '~'
      skip_quoted_form(source, index + 1, limit)
    else
      symbol, after = read_symbol(source, i, limit)
      # Auto-gensyms (`foo#`) only occur in macro templates, never as handler
      # references — leave them out.
      unless skip_callee?(symbol) || symbol.ends_with?('#')
        entries << {symbol, file_path, line_number_for(source, index, start_line)}
      end
      after > i ? after : i + 1
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

    # `index`/`i` are byte offsets (advanced via byte_at), so slice by bytes —
    # char-indexing here corrupts every name after a multi-byte UTF-8 char.
    {source.byte_slice(index, i - index), i}
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
end
