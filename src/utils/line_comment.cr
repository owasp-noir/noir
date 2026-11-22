module Noir::LineComment
  # Prefix before an unquoted marker on one line. Both quote styles honor
  # backslash escapes. Callers that track heredocs do so across lines.
  def self.strip(line : String, marker : Char) : String
    return line unless line.includes?(marker)

    quote = nil
    escaped = false
    line.each_char_with_index do |char, index|
      if quote
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == quote
          quote = nil
        end
      elsif char.in?('"', '\'')
        quote = char
      elsif char == marker
        return line[0, index]
      end
    end
    line
  end
end
