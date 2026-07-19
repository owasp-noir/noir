require "../../models/analyzer"
require "../../utils/utils.cr"

module Analyzer::Cfml
  # Shared CFML parsing layer.
  #
  # See AGENTS.md §"Analyzer Layering": this owns file selection and the
  # syntax handling every CFML adapter needs, so framework analyzers
  # (Taffy, ColdBox, Wheels, FW/1) consume components and functions
  # rather than re-implementing tag/script parsing.
  #
  # The two syntaxes are the whole problem. CFML is written either as
  # tags (`<cffunction name="x" access="remote">`) or as cfscript
  # (`remote string function x()`), the two mix inside a single file, and
  # everything is case-insensitive.
  abstract class CfmlEngine < Analyzer
    # Tags may span lines and pad their `=` for alignment, so attributes
    # are matched with `\s*=\s*` and tag bodies with `[\s\S]*?`.
    CFCOMPONENT_TAG_RE = /<cfcomponent\b([\s\S]*?)>/i
    CFFUNCTION_TAG_RE  = /<cffunction\b([\s\S]*?)>/i
    CFARGUMENT_TAG_RE  = /<cfargument\b([\s\S]*?)>/i

    # Attribute names carry `:` and `-` in the wild (`taffy:uri`,
    # `data-required`), and values use either quote style.
    TAG_ATTR_RE = /([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/

    # `component ... {` header in script syntax, and a function
    # declaration with its trailing attribute list up to the body brace.
    SCRIPT_COMPONENT_RE = /(?<![\w.])component\b/i
    SCRIPT_FUNCTION_RE  = /(?<![\w.])function\s+(\w+)\s*\(/i

    # A component header is a handful of attributes; bound the scan so a
    # file with no opening brace cannot walk the whole content.
    SCRIPT_COMPONENT_HEADER_LIMIT = 2000

    # Verbs a CFML framework can register. Route DSLs take verbs as free
    # text, so a value outside this set is not turned into a method.
    HTTP_VERBS = Set{"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"}

    NAMED_ARGUMENT_RE = /\A([A-Za-z_]\w*)\s*[:=]\s*(.+)\z/m

    # TestBox names suites `<Something>Test.cfc` / `<Something>Spec.cfc`.
    # The leading `.+` is load-bearing: a component named exactly
    # `Test.cfc` is a demo, not a suite (fw1 ships one that declares a
    # real `remote` method), and an anchored `ends_with?` swallowed it.
    TEST_COMPONENT_RE = /.+(?:Test|Spec)\.cfc\z/i

    private BYTE_LT            = '<'.ord.to_u8
    private BYTE_BANG          = '!'.ord.to_u8
    private BYTE_DASH          = '-'.ord.to_u8
    private BYTE_GT            = '>'.ord.to_u8
    private BYTE_NEWLINE       = '\n'.ord.to_u8
    private BYTE_SEMICOLON     = ';'.ord.to_u8
    private BYTE_OPEN_BRACE    = '{'.ord.to_u8
    private BYTE_CLOSE_BRACE   = '}'.ord.to_u8
    private BYTE_SPACE         = ' '.ord.to_u8
    private BYTE_TAB           = '\t'.ord.to_u8
    private BYTE_RETURN        = '\r'.ord.to_u8
    private BYTE_OPEN_PAREN    = '('.ord.to_u8
    private BYTE_CLOSE_PAREN   = ')'.ord.to_u8
    private BYTE_OPEN_BRACKET  = '['.ord.to_u8
    private BYTE_CLOSE_BRACKET = ']'.ord.to_u8
    private BYTE_DQUOTE        = '"'.ord.to_u8
    private BYTE_SQUOTE        = '\''.ord.to_u8

    # Route registrations are statements. An identifier as generic as
    # `get` or `delete` also appears inside expressions
    # (`if ( get( "featureFlag" ) )`), so a call only counts when nothing
    # but horizontal whitespace separates it from a statement boundary.
    #
    # A newline counts as a boundary in its own right. `//` line comments
    # are not stripped (only `<!--- --->` is), so requiring `;`/`{`/`}`
    # would reject every call preceded by a comment line — which is most
    # of a real router.
    protected def statement_start?(content : String, index : Int32) : Bool
      bytes = content.to_slice
      position = content.char_index_to_byte_index(index)
      return true if position.nil? || position == 0

      position -= 1
      while position >= 0
        byte = bytes[position]
        return true if byte == BYTE_NEWLINE || byte == BYTE_RETURN
        return true if byte == BYTE_SEMICOLON || byte == BYTE_OPEN_BRACE || byte == BYTE_CLOSE_BRACE
        return false unless byte == BYTE_SPACE || byte == BYTE_TAB

        position -= 1
      end

      true
    end

    protected def cfml_components : Array(String)
      get_files_by_extension(".cfc").reject { |path| File.directory?(path) || cfml_test_path?(path) }
    end

    protected def cfml_pages : Array(String)
      (get_files_by_extension(".cfm") + get_files_by_extension(".cfml"))
        .uniq!
        .reject { |path| File.directory?(path) || cfml_test_path?(path) }
    end

    protected def cfml_test_path?(path : String) : Bool
      return true if path.includes?("/tests/") || path.includes?("/test/")

      File.basename(path).matches?(TEST_COMPONENT_RE)
    end

    # `<cfargument>` tags belong to the function they follow, so scan only
    # up to the matching `</cffunction>` (or the next `<cffunction>` when
    # the closing tag is missing).
    protected def tag_arguments(content : String, from : Int32) : Array(String)
      close = content.index(/<\/cffunction>/i, from)
      next_function = content.index(/<cffunction\b/i, from)
      stop = [close, next_function].compact.min? || content.size

      names = [] of String
      content[from...stop].scan(CFARGUMENT_TAG_RE) do |argument|
        name = tag_attributes(argument[1])["name"]?
        names << name if name && !name.empty?
      end
      names
    end

    protected def tag_attributes(raw : String) : Hash(String, String)
      attributes = {} of String => String
      raw.scan(TAG_ATTR_RE) do |match|
        attributes[match[1].downcase] = match[2]? || match[3]? || ""
      end
      attributes
    end

    # Argument names from a script-syntax signature. Handles `name`,
    # `type name`, `required type name` and `type name="default"`.
    # Stopping at the first `=` also drops Taffy's inline per-argument
    # validators, which follow the default with no separating comma:
    # `string name = "" taffy_minlength="1"`.
    protected def script_arguments(raw : String) : Array(String)
      names = [] of String

      split_arguments(raw).each do |chunk|
        declaration = chunk.split('=').first.strip
        next if declaration.empty?

        name = declaration.split(/\s+/).last?
        next if name.nil? || !name.matches?(/\A[A-Za-z_]\w*\z/)

        names << name
      end

      names
    end

    # Split on commas at nesting depth zero, so a comma inside a default
    # value or a nested call does not start a new argument.
    protected def split_arguments(raw : String) : Array(String)
      chunks = [] of String
      current = String::Builder.new
      depth = 0
      quote = nil.as(Char?)

      raw.each_char do |char|
        if quote
          quote = nil if char == quote
          current << char
          next
        end

        case char
        when '"', '\''
          quote = char
          current << char
        when '(', '[', '{'
          depth += 1
          current << char
        when ')', ']', '}'
          depth -= 1
          current << char
        when ','
          if depth == 0
            chunks << current.to_s
            current = String::Builder.new
          else
            current << char
          end
        else
          current << char
        end
      end

      chunks << current.to_s
      chunks.map(&.strip).reject(&.empty?)
    end

    # Arguments of a CFML function call: positional ones keyed "0", "1",
    # ..., named ones by their downcased name. Only literals resolve — a
    # value built at runtime is not something to report as a route.
    # `##` is CFML's escape for a literal `#`.
    protected def call_arguments(raw : String) : Hash(String, String)
      arguments = {} of String => String

      split_arguments(raw).each_with_index do |chunk, index|
        if match = chunk.match(NAMED_ARGUMENT_RE)
          if value = argument_literal(match[2])
            arguments[match[1].downcase] = value
          end
        elsif value = argument_literal(chunk)
          arguments[index.to_s] = value
        end
      end

      arguments
    end

    protected def argument_literal(raw : String) : String?
      stripped = raw.strip

      if match = stripped.match(/\A"([^"]*)"\z/)
        return match[1].gsub("##", "#")
      end

      if match = stripped.match(/\A'([^']*)'\z/)
        return match[1].gsub("##", "#")
      end

      # Bare booleans reach flags such as `nested=true`.
      stripped.matches?(/\A(?:true|false)\z/i) ? stripped : nil
    end

    protected def paren_content(content : String, open_paren : Int32) : String?
      close = matching_paren(content, open_paren)
      close ? content[(open_paren + 1)...close] : nil
    end

    protected def matching_paren(content : String, open_paren : Int32) : Int32?
      matching_delimiter(content, open_paren, BYTE_OPEN_PAREN, BYTE_CLOSE_PAREN)
    end

    protected def matching_bracket(content : String, open_bracket : Int32) : Int32?
      matching_delimiter(content, open_bracket, BYTE_OPEN_BRACKET, BYTE_CLOSE_BRACKET)
    end

    # Index of the delimiter closing the one at `open_index`.
    #
    # Byte scan rather than `String#[](Int)`, which is O(n) per access on
    # strings holding multi-byte characters and would make this O(n^2) —
    # the same trap `PhpEngine#find_matching_php_close_brace` documents
    # after CJK-commented sources hung the PHP analyzer. Every delimiter
    # is ASCII, so it can never collide with a UTF-8 continuation byte.
    protected def matching_delimiter(content : String, open_index : Int32,
                                     open_byte : UInt8, close_byte : UInt8) : Int32?
      bytes = content.to_slice
      start = content.char_index_to_byte_index(open_index)
      return unless start && start < bytes.size && bytes[start] == open_byte

      depth = 0
      position = start
      size = bytes.size
      quote = 0_u8

      while position < size
        byte = bytes[position]

        if quote != 0_u8
          quote = 0_u8 if byte == quote
        elsif byte == BYTE_DQUOTE || byte == BYTE_SQUOTE
          quote = byte
        elsif byte == open_byte
          depth += 1
        elsif byte == close_byte
          depth -= 1
          return content.byte_index_to_char_index(position) if depth == 0
        end

        position += 1
      end

      nil
    end

    # Strip `<!--- ... --->` blocks. CFML comments nest, and a file may
    # be almost entirely comment (MasaCMS opens every file with a ~70
    # line licence header, sometimes closing on the same line as real
    # code), so this cannot be line-oriented. Newlines inside comments
    # are preserved so reported line numbers stay accurate.
    protected def strip_cfml_comments(content : String) : String
      return content unless content.includes?("<!---")

      bytes = content.to_slice
      size = bytes.size
      io = IO::Memory.new(size)
      index = 0
      depth = 0

      while index < size
        if index + 4 < size && bytes[index] == BYTE_LT && bytes[index + 1] == BYTE_BANG &&
           bytes[index + 2] == BYTE_DASH && bytes[index + 3] == BYTE_DASH && bytes[index + 4] == BYTE_DASH
          depth += 1
          # Advance to the final dash of the opener, not past it: engines
          # accept `<!----->`, where the closer overlaps the opener on
          # that shared dash. Consuming all five stranded the `-->` tail
          # and silently discarded the rest of the file.
          index += 4
        elsif depth > 0 && index + 3 < size && bytes[index] == BYTE_DASH && bytes[index + 1] == BYTE_DASH &&
              bytes[index + 2] == BYTE_DASH && bytes[index + 3] == BYTE_GT
          depth -= 1
          index += 4
        else
          if depth == 0
            io.write_byte(bytes[index])
          elsif bytes[index] == BYTE_NEWLINE
            io.write_byte(BYTE_NEWLINE)
          end
          index += 1
        end
      end

      io.to_s
    end

    # Blank cfscript `//` and `/* */` comments, keeping newlines so line
    # numbers hold.
    #
    # This matters more than it looks. Route files are heavily commented,
    # and the generated comments quote the DSL they describe — Wheels
    # ships `// The "wildcard" call below ...` and a commented-out
    # `// .wildcard()`. Scanning raw content let a comment that merely
    # mentions `mapper()` move the start of the chain, so unrelated calls
    # before the real chain were read as routes.
    #
    # The scan is string-aware: CFML escapes a quote by doubling it, and
    # `//` occurs inside ordinary string values (URLs).
    protected def strip_script_comments(content : String) : String
      return content unless content.includes?("//") || content.includes?("/*")

      chars = content.chars
      size = chars.size
      io = String::Builder.new(content.bytesize)
      index = 0
      quote = nil.as(Char?)

      while index < size
        char = chars[index]

        if quote
          quote = nil if char == quote
          io << char
          index += 1
          next
        end

        case
        when char == '"' || char == '\''
          quote = char
          io << char
          index += 1
        when char == '/' && chars[index + 1]? == '/'
          while index < size && chars[index] != '\n'
            io << ' '
            index += 1
          end
        when char == '/' && chars[index + 1]? == '*'
          io << "  "
          index += 2
          while index < size && !(chars[index] == '*' && chars[index + 1]? == '/')
            io << (chars[index] == '\n' ? '\n' : ' ')
            index += 1
          end
          if index < size
            io << "  "
            index += 2
          end
        else
          io << char
          index += 1
        end
      end

      io.to_s
    end

    # Both comment syntaxes, for analyzers that scan cfscript.
    protected def strip_all_comments(content : String) : String
      strip_script_comments(strip_cfml_comments(content))
    end

    # Attributes on the `<cfcomponent>` tag or the script `component`
    # header, whichever the file uses.
    protected def component_attributes(content : String) : Hash(String, String)
      if match = content.match(CFCOMPONENT_TAG_RE)
        return tag_attributes(match[1])
      end

      if match = content.match(SCRIPT_COMPONENT_RE)
        if start = match.end(0)
          window = content[start, SCRIPT_COMPONENT_HEADER_LIMIT]? || ""
          return tag_attributes(attributes_before_body(window))
        end
      end

      {} of String => String
    end

    # Everything up to the first `{` that is *not* inside a quoted value.
    # Attribute values legitimately contain braces — Taffy writes
    # `taffy:uri="/items/{id}"` — so cutting at the first brace truncated
    # the header mid-value and silently dropped every tokenised route.
    private def attributes_before_body(window : String) : String
      quote = nil.as(Char?)

      window.each_char_with_index do |char, index|
        if quote
          quote = nil if char == quote
          next
        end

        case char
        when '"', '\'' then quote = char
        when '{'       then return window[0...index]
        end
      end

      window
    end
  end
end
