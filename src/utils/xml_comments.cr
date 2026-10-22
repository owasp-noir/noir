require "xml"

# XML comments, removed before anything reads the document.
#
# libxml2 copies the comment text parsed so far into every error it raises
# inside a comment, and `--` inside a comment is an error. A comment holding
# many `--`, or a run of unterminated `<!--` (each one nests in the last),
# made `XML.parse` quadratic: a 1.6 MB web.xml cost over 20 seconds of CPU.
# No analyzer reads comment nodes, so they are dropped in one linear pass
# before libxml2 sees them.
module Noir::XmlComments
  # `content` with each `<!-- ... -->` replaced by the newlines it spanned,
  # so line numbers still match the source. An unterminated `<!--` runs to
  # the end of the document, as an XML parser reads it. CDATA sections pass
  # through untouched: a `<!--` inside one is text, not a comment. So do
  # processing instructions and the DOCTYPE (an entity value may hold a
  # `<!--`); a comment inside the internal subset is left for libxml2.
  def self.strip(content : String) : String
    return content unless content.includes?("<!--")

    bytes = content.to_slice
    String.build(content.bytesize) do |io|
      pos = 0
      cursor = 0
      while lt = content.byte_index('<', cursor)
        if at?(bytes, lt, "<!--")
          io.write(bytes[pos, lt - pos])
          stop = past(content, "-->", lt + 4)
          bytes[lt, stop - lt].each { |byte| io.write_byte(byte) if byte == 10 }
          pos = cursor = stop
        elsif at?(bytes, lt, "<![CDATA[")
          cursor = past(content, "]]>", lt + 9)
        elsif at?(bytes, lt, "<?")
          cursor = past(content, "?>", lt + 2)
        elsif at?(bytes, lt, "<!DOCTYPE")
          # Up to the first `[` or `>` only: searching for each separately
          # rescans the file from every repeated `<!DOCTYPE`.
          i = lt + 9
          while i < bytes.size && bytes[i] != '['.ord && bytes[i] != '>'.ord
            i += 1
          end
          cursor = i < bytes.size && bytes[i] == '['.ord ? past(content, "]>", i) : i + 1
        else
          cursor = lt + 1
        end
      end
      io.write(bytes[pos, bytes.size - pos])
    end
  end

  private def self.at?(bytes : Bytes, index : Int32, token : String) : Bool
    index + token.bytesize <= bytes.size && bytes[index, token.bytesize] == token.to_slice
  end

  # Byte offset just past the next `token` from `from`, or the end.
  private def self.past(content : String, token : String, from : Int32) : Int32
    found = content.byte_index(token, from)
    found ? found + token.bytesize : content.bytesize
  end

  # `XML.parse` on the comment-free document.
  def self.parse(content : String, options : XML::ParserOptions = XML::ParserOptions.default) : XML::Node
    XML.parse(strip(content), options)
  end
end
