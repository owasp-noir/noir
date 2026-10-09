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
  # through untouched: a `<!--` inside one is text, not a comment.
  def self.strip(content : String) : String
    open = content.byte_index("<!--")
    return content unless open

    cdata = content.byte_index("<![CDATA[")
    String.build(content.bytesize) do |io|
      pos = 0
      while open
        if cdata && cdata < open
          close = content.byte_index("]]>", cdata + 9)
          stop = close ? close + 3 : content.bytesize
          io.write(content.to_slice[pos, stop - pos])
        else
          io.write(content.to_slice[pos, open - pos])
          close = content.byte_index("-->", open + 4)
          stop = close ? close + 3 : content.bytesize
          content.to_slice[open, stop - open].each { |byte| io.write_byte(byte) if byte == 10 }
        end
        pos = stop
        cdata = content.byte_index("<![CDATA[", pos) if cdata && cdata < pos
        open = content.byte_index("<!--", pos)
      end
      io.write(content.to_slice[pos, content.bytesize - pos])
    end
  end

  # `XML.parse` on the comment-free document.
  def self.parse(content : String, options : XML::ParserOptions = XML::ParserOptions.default) : XML::Node
    XML.parse(strip(content), options)
  end
end
