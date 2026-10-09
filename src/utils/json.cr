require "json"

# `parse_json_lenient`-or-nil.
def json_any?(content : String) : JSON::Any?
  parse_json_lenient(content)
rescue
  nil
end

# `JSON.parse`, recovering from a number Crystal cannot represent.
#
# Crystal's JSON lexer raises on an integer beyond Int64 or a float beyond
# Float64 (`18446744073709551615`, `1e400`) — valid JSON that other parsers
# accept — and one such `maximum` or example id cost the whole document. On
# that failure only, the out-of-range literals are re-read as strings of
# their raw text and the parse retried. Nothing noir reads from a spec
# document depends on such a number's value, and line numbers are unchanged.
def parse_json_lenient(content : String) : JSON::Any
  JSON.parse(content)
rescue ex : JSON::ParseException
  raise ex unless ex.message.try(&.starts_with?(/Invalid (?:Int|Float)64/))
  raise ex unless quoted = quote_out_of_range_json_numbers(content)
  JSON.parse(quoted)
end

private JSON_NUMBER = /\A-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?\z/

# `content` with every well-formed but out-of-range number literal outside a
# string quoted, or nil when there is none.
private def quote_out_of_range_json_numbers(content : String) : String?
  bytes = content.to_slice
  changed = false
  quoted = String.build(content.bytesize + 16) do |io|
    copied = 0
    i = 0
    in_string = false
    while i < bytes.size
      byte = bytes[i]
      if in_string
        if byte == '\\'.ord
          i += 2
          next
        end
        in_string = false if byte == '"'.ord
        i += 1
      elsif byte == '"'.ord
        in_string = true
        i += 1
      elsif byte == '-'.ord || byte.unsafe_chr.ascii_number?
        stop = i
        while stop < bytes.size && "0123456789+-.eE".includes?(bytes[stop].unsafe_chr)
          stop += 1
        end
        token = String.new(bytes[i, stop - i])
        if token.matches?(JSON_NUMBER) && out_of_range_json_number?(token)
          io.write(bytes[copied, i - copied])
          io << '"' << token << '"'
          copied = stop
          changed = true
        end
        i = stop
      else
        i += 1
      end
    end
    io.write(bytes[copied, bytes.size - copied])
  end
  quoted if changed
end

private def out_of_range_json_number?(token : String) : Bool
  if token.each_char.any? { |char| char == '.' || char == 'e' || char == 'E' }
    token.to_f64?.nil?
  else
    token.to_i64?.nil?
  end
end
