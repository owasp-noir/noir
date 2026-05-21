# Tnetstring decoder used by the mitmproxy flow analyzer.
#
# Format (https://tnetstrings.info/):
#   <length>:<payload><type>
# Types: "," string, "#" integer, "^" float, "!" boolean, "~" null,
#        "]" list, "}" dict.
#
# mitmproxy ships a small extension over the base format: a `;` type
# byte denoting raw bytes alongside `,`. We accept both and surface
# them as Crystal `String`, which is what every caller of this module
# wants today.
module Tnetstring
  alias Value = String? | Int64 | Bool | Float64 | Array(Value) | Hash(String, Value)

  class ParseError < Exception
  end

  COLON    = ':'.ord.to_u8
  STR_TYPE = ','.ord.to_u8
  # mitmproxy's tnetstring variant adds a separate `;` type for raw
  # bytes alongside the standard `,` string type. Decoding both as
  # Crystal String is fine — they are interchangeable to the
  # consumer; we only need to handle the type byte either way.
  BYTES_TYPE = ';'.ord.to_u8
  INT_TYPE   = '#'.ord.to_u8
  FLOAT_TYP  = '^'.ord.to_u8
  BOOL_TYPE  = '!'.ord.to_u8
  NULL_TYPE  = '~'.ord.to_u8
  LIST_TYPE  = ']'.ord.to_u8
  DICT_TYPE  = '}'.ord.to_u8

  # Parses one tnetstring value starting at byte offset `pos`.
  # Returns the decoded value and the next read position.
  def self.parse(bytes : Bytes, pos : Int32 = 0) : Tuple(Value, Int32)
    raise ParseError.new("unexpected end of input") if pos >= bytes.size

    colon = pos
    while colon < bytes.size && bytes[colon] != COLON
      raise ParseError.new("invalid length digit at #{colon}") unless bytes[colon] >= '0'.ord.to_u8 && bytes[colon] <= '9'.ord.to_u8
      colon += 1
    end
    raise ParseError.new("missing length separator") if colon >= bytes.size
    raise ParseError.new("empty length prefix") if colon == pos

    length_str = String.new(bytes[pos, colon - pos])
    length = length_str.to_i? || raise ParseError.new("invalid length: #{length_str}")
    raise ParseError.new("negative length") if length < 0

    payload_start = colon + 1
    payload_end = payload_start + length
    raise ParseError.new("payload out of bounds") if payload_end >= bytes.size

    payload = bytes[payload_start, length]
    type_byte = bytes[payload_end]
    next_pos = payload_end + 1

    {decode(type_byte, payload), next_pos}
  end

  # Parses every top-level tnetstring value in `bytes`. The mitmproxy
  # flow file format concatenates flows as a stream of dict values
  # with no framing beyond tnetstring itself.
  def self.parse_all(bytes : Bytes) : Array(Value)
    result = [] of Value
    pos = 0
    while pos < bytes.size
      value, pos = parse(bytes, pos)
      result << value
    end
    result
  end

  private def self.decode(type_byte : UInt8, payload : Bytes) : Value
    case type_byte
    when STR_TYPE, BYTES_TYPE
      String.new(payload)
    when INT_TYPE
      String.new(payload).to_i64? || raise ParseError.new("invalid integer payload")
    when FLOAT_TYP
      String.new(payload).to_f64? || raise ParseError.new("invalid float payload")
    when BOOL_TYPE
      s = String.new(payload)
      case s
      when "true"  then true
      when "false" then false
      else              raise ParseError.new("invalid boolean payload: #{s}")
      end
    when NULL_TYPE
      raise ParseError.new("null payload must be empty") unless payload.size == 0
      nil
    when LIST_TYPE
      list = [] of Value
      pos = 0
      while pos < payload.size
        v, pos = parse(payload, pos)
        list << v
      end
      list
    when DICT_TYPE
      dict = {} of String => Value
      pos = 0
      while pos < payload.size
        k, pos = parse(payload, pos)
        v, pos = parse(payload, pos)
        raise ParseError.new("dict key must be a string") unless k.is_a?(String)
        dict[k] = v
      end
      dict
    else
      raise ParseError.new("unknown type byte: #{type_byte.chr.inspect}")
    end
  end

  # Encoder — currently used by specs to build flow fixtures
  # programmatically, but kept in the production module so the
  # implementation is exercised by the same tests as the decoder.
  def self.encode(value : Value) : Bytes
    io = IO::Memory.new
    encode(value, io)
    io.to_slice
  end

  def self.encode(value : Value, io : IO) : Nil
    case value
    when String
      bytes = value.to_slice
      io << bytes.size << ":"
      io.write(bytes)
      io << ","
    when Bool
      s = value ? "true" : "false"
      io << s.bytesize << ":" << s << "!"
    when Int64
      s = value.to_s
      io << s.bytesize << ":" << s << "#"
    when Float64
      s = value.to_s
      io << s.bytesize << ":" << s << "^"
    when Nil
      io << "0:~"
    when Array
      inner = IO::Memory.new
      value.each { |v| encode(v, inner) }
      io << inner.bytesize << ":"
      io.write(inner.to_slice)
      io << "]"
    when Hash
      inner = IO::Memory.new
      value.each do |k, v|
        encode(k.as(Value), inner)
        encode(v, inner)
      end
      io << inner.bytesize << ":"
      io.write(inner.to_slice)
      io << "}"
    end
  end
end
