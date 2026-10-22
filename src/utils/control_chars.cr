# Renders C0/C1 control characters — the escape sequences a terminal acts
# on — as visible `\xNN` text.
#
# Everything a report prints comes out of the repo being scanned, which is
# the one thing Noir never trusts: a route literal
# `"/x\e]8;;http://evil.example\aclick\e]8;;\a"` was replayed verbatim into
# the terminal, where it rendered as a clickable link to the attacker's host
# instead of as the string the source actually contains. `\e[2J`, `\ec` and
# a bare newline in a param name are the same problem with a different
# payload: the report stops describing the code and starts obeying it.
#
# Escaped rather than stripped so the report still says what is there —
# `-f json` shows the byte as `\u001b`, and this is that fact in plain text.
# Only the control blocks are touched, so a CJK route or a `£` in a param
# value passes through unchanged.
#
# Shared by every builder that writes repo text to stdout, and by the
# command builders (`CurlCommand`, `MobileLaunch`) that quote it.
module ControlChars
  def self.escape(text : String) : String
    return text unless may_contain?(text)

    String.build do |io|
      text.each_char do |char|
        if control?(char)
          io << "\\x" << char.ord.to_s(16).rjust(2, '0')
        else
          io << char
        end
      end
    end
  end

  def self.control?(char : Char) : Bool
    ord = char.ord
    ord < 0x20 || ord == 0x7f || (0x80 <= ord <= 0x9f)
  end

  # Byte-level prefilter so the common (clean) string never pays for a
  # char-by-char walk. C1 controls are two bytes in UTF-8 and always start
  # with 0xC2, which also introduces `\u00a0`-`\u00bf`; those fall through to
  # `control?` and are left alone.
  def self.may_contain?(text : String) : Bool
    text.each_byte do |byte|
      return true if byte < 0x20 || byte == 0x7f || byte == 0xc2
    end
    false
  end
end
