require "../utils/c_comments"
require "../utils/top_level_split"

module Noir
  # Salesforce Apex declaration scanner. A `.cls` file holds one top-level
  # class; this yields its header and the members declared directly in its
  # body. Inner-class members are skipped: Apex only exposes REST, Aura and
  # `webservice` entry points on top-level classes.
  #
  # Apex keywords and annotations are case-insensitive, so annotation names
  # are returned lowercased. String literals are single-quoted only.
  module ApexExtractor
    extend self

    record Member,
      annotations : Array(String),
      header : String,
      name : String,
      args : Array(String),
      body : String,
      line : Int32

    record ApexClass,
      name : String,
      header : String,
      annotations : Array(String),
      members : Array(Member)

    CLASS_RE      = /\bclass\s+(\w+)/i
    ANNOTATION_RE = /@(\w+)/
    # A method header ends with `name(args)`; properties and inner classes
    # (`String name { get; }`, `class Inner {`) do not.
    SIGNATURE_RE = /(\w+)\s*\(([^()]*)\)\s*\z/
    ARGS         = TopLevelSplit::Rules.new(nest: TopLevelSplit::Nest::Angle, quotes: "'", empties: TopLevelSplit::Empties::DropAll)

    QUOTE     = '\''.ord.to_u8
    BACKSLASH = '\\'.ord.to_u8
    OPEN      = '{'.ord.to_u8
    CLOSE     = '}'.ord.to_u8
    SEMI      = ';'.ord.to_u8
    NEWLINE   = '\n'.ord.to_u8

    def parse(source : String) : ApexClass?
      src = CComments.strip(source, quotes: "'")
      bytes = src.to_slice
      class_open = next_open(bytes, 0) || return
      header = String.new(bytes[0, class_open])
      name = header.match(CLASS_RE).try(&.[1]) || return
      class_close = close_of(bytes, class_open)

      members = [] of Member
      line = 1
      line_pos = 0
      start = class_open + 1
      i = start
      while i < class_close
        case bytes[i]
        when QUOTE
          i = skip_string(bytes, i)
        when SEMI, CLOSE
          start = i + 1
        when OPEN
          close = close_of(bytes, i)
          member_header = String.new(bytes[start, i - start])
          if sig = member_header.rstrip.match(SIGNATURE_RE)
            offset = start + (member_header.bytesize - member_header.lstrip.bytesize)
            line += bytes[line_pos, offset - line_pos].count(NEWLINE)
            line_pos = offset
            members << Member.new(
              annotations(member_header), member_header, sig[1], arg_names(sig[2]),
              String.new(bytes[i + 1, close - i - 1]), line)
          end
          i = close
          start = close + 1
        end
        i += 1
      end

      ApexClass.new(name, header, annotations(header), members)
    end

    private def annotations(header : String) : Array(String)
      header.scan(ANNOTATION_RE).map(&.[1].downcase)
    end

    # `List<String> ids, Map<String, Object> opts` -> ["ids", "opts"].
    private def arg_names(args : String) : Array(String)
      TopLevelSplit.split(args, ',', ARGS).compact_map(&.split.last?)
    end

    private def next_open(bytes : Bytes, from : Int32) : Int32?
      i = from
      while i < bytes.size
        return i if bytes[i] == OPEN
        i = skip_string(bytes, i) if bytes[i] == QUOTE
        i += 1
      end
    end

    # Index of the `}` closing the `{` at `open` (or the end of input).
    private def close_of(bytes : Bytes, open : Int32) : Int32
      depth = 0
      i = open
      while i < bytes.size
        case bytes[i]
        when QUOTE
          i = skip_string(bytes, i)
        when OPEN
          depth += 1
        when CLOSE
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end
      bytes.size
    end

    # Index of the quote closing the literal opened at `i`.
    private def skip_string(bytes : Bytes, i : Int32) : Int32
      i += 1
      while i < bytes.size
        return i if bytes[i] == QUOTE
        i += 1 if bytes[i] == BACKSLASH
        i += 1
      end
      i
    end
  end
end
