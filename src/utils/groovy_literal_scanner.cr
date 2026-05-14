module Noir::GroovyLiteralScanner
  extend self

  SLASHY_PRECEDING_CHARS = [
    '(', '[', '{', ',', ':', ';', '=', '!', '&', '|', '?',
    '+', '-', '*', '%', '<', '>', '~',
  ]

  SLASHY_PRECEDING_KEYWORDS = Set{
    "assert", "case", "in", "return", "throw",
  }

  def skip_literal(content : String, pos : Int32) : Int32?
    return if pos >= content.size

    char = content[pos]

    return skip_dollar_slashy(content, pos) if dollar_slashy_start?(content, pos)
    return skip_triple_quote(content, pos, char) if triple_quote_start?(content, pos, char)
    return skip_quoted(content, pos, char) if char == '"' || char == '\''
    return skip_slashy(content, pos) if slashy_start?(content, pos)

    nil
  end

  private def dollar_slashy_start?(content : String, pos : Int32) : Bool
    pos + 1 < content.size && content[pos] == '$' && content[pos + 1] == '/'
  end

  private def triple_quote_start?(content : String, pos : Int32, quote : Char) : Bool
    return false unless quote == '"' || quote == '\''

    pos + 2 < content.size &&
      content[pos] == quote &&
      content[pos + 1] == quote &&
      content[pos + 2] == quote
  end

  private def slashy_start?(content : String, pos : Int32) : Bool
    return false unless content[pos] == '/'
    return false if pos + 1 < content.size && {'/', '*', '='}.includes?(content[pos + 1])

    prev = previous_nonspace_index(content, pos)
    return true unless prev

    prev_char = content[prev]
    return true if SLASHY_PRECEDING_CHARS.includes?(prev_char)

    word = previous_word(content, prev)
    SLASHY_PRECEDING_KEYWORDS.includes?(word)
  end

  private def previous_nonspace_index(content : String, pos : Int32) : Int32?
    index = pos - 1
    while index >= 0
      return index unless content[index].whitespace?
      index -= 1
    end
    nil
  end

  private def previous_word(content : String, word_end : Int32) : String
    end_exclusive = word_end + 1
    index = word_end
    while index >= 0 && identifier_char?(content[index])
      index -= 1
    end

    content[(index + 1)...end_exclusive]
  end

  private def identifier_char?(char : Char) : Bool
    char.alphanumeric? || char == '_' || char == '$'
  end

  private def skip_quoted(content : String, pos : Int32, quote : Char) : Int32
    index = pos + 1
    while index < content.size
      if content[index] == '\\' && index + 1 < content.size
        index += 2
        next
      end

      if content[index] == quote
        return index + 1
      end

      index += 1
    end

    content.size
  end

  private def skip_triple_quote(content : String, pos : Int32, quote : Char) : Int32
    index = pos + 3
    while index + 2 < content.size
      if content[index] == quote &&
         content[index + 1] == quote &&
         content[index + 2] == quote &&
         !escaped?(content, index)
        return index + 3
      end

      index += 1
    end

    content.size
  end

  private def skip_dollar_slashy(content : String, pos : Int32) : Int32
    index = pos + 2
    while index + 1 < content.size
      if content[index] == '/' &&
         content[index + 1] == '$' &&
         !escaped_dollar_slashy_delimiter?(content, pos, index)
        return index + 2
      end

      index += 1
    end

    content.size
  end

  private def skip_slashy(content : String, pos : Int32) : Int32
    index = pos + 1
    while index < content.size
      if content[index] == '\\' && index + 1 < content.size
        index += 2
        next
      end

      return index + 1 if content[index] == '/'

      index += 1
    end

    content.size
  end

  private def escaped?(content : String, pos : Int32) : Bool
    backslashes = 0
    index = pos - 1
    while index >= 0 && content[index] == '\\'
      backslashes += 1
      index -= 1
    end

    backslashes.odd?
  end

  private def escaped_dollar_slashy_delimiter?(content : String, start : Int32, slash_pos : Int32) : Bool
    slash_pos > start + 2 && content[slash_pos - 1] == '$'
  end
end
