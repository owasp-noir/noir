module Noir
  # Reads the parts of an Apache Thrift IDL document that describe an RPC
  # surface: `include` headers and `service` definitions with their
  # functions. Structs, enums, consts and typedefs are skipped.
  #
  # The parser works on tokens rather than lines because Thrift is
  # whitespace-free: a function may span several lines, fields may be
  # separated by `,`, `;` or nothing at all, and annotations
  # (`(key = "value")`) can follow a type, a field, a function or a service.
  module ThriftIdl
    record Field, id : String?, requiredness : String?, type : String, name : String, line : Int32
    record Function, name : String, return_type : String, oneway : Bool, args : Array(Field), line : Int32
    record Service, name : String, extends : String?, functions : Array(Function), line : Int32
    record Document, includes : Array(String), services : Array(Service)

    enum Kind
      Ident
      Str
      Number
      Punct
    end

    record Token, kind : Kind, text : String, line : Int32

    # Words that may precede a function's return type. `oneway` is Apache
    # Thrift; `readonly` and `idempotent` are fbthrift qualifiers.
    FUNCTION_QUALIFIERS = Set{"oneway", "readonly", "idempotent"}
    SEPARATORS          = Set{",", ";"}

    # Blanks `//`, `/* */` and `#` comments, keeping every newline so line
    # numbers in the result match the original. Quoted literals (single or
    # double) are kept verbatim, so a `#` or `//` inside an annotation value
    # is not mistaken for a comment.
    def self.strip_comments(text : String) : String
      return text unless text.includes?('#') || text.includes?("//") || text.includes?("/*")

      chars = text.chars
      size = chars.size
      String.build(text.bytesize) do |io|
        i = 0
        while i < size
          c = chars[i]
          if c == '"' || c == '\''
            j = string_end(chars, i)
            (i...j).each { |k| io << chars[k] }
            i = j
          elsif c == '#' || (c == '/' && i + 1 < size && chars[i + 1] == '/')
            while i < size && chars[i] != '\n'
              io << ' '
              i += 1
            end
          elsif c == '/' && i + 1 < size && chars[i + 1] == '*'
            io << "  "
            i += 2
            while i < size && !(chars[i] == '*' && i + 1 < size && chars[i + 1] == '/')
              io << (chars[i] == '\n' ? '\n' : ' ')
              i += 1
            end
            if i < size
              io << "  "
              i += 2
            end
          else
            io << c
            i += 1
          end
        end
      end
    end

    # Index just past the literal opened at `start`. An unterminated literal
    # runs to the end of its line, as the Thrift lexer refuses line breaks
    # inside literals.
    private def self.string_end(chars : Array(Char), start : Int32) : Int32
      quote = chars[start]
      i = start + 1
      while i < chars.size
        c = chars[i]
        return i + 1 if c == quote
        return i if c == '\n'
        i += c == '\\' ? 2 : 1
      end
      chars.size
    end

    def self.tokenize(text : String) : Array(Token)
      tokens = [] of Token
      chars = text.chars
      size = chars.size
      line = 1
      i = 0
      while i < size
        c = chars[i]
        if c == '\n'
          line += 1
          i += 1
        elsif c.whitespace?
          i += 1
        elsif c.ascii_letter? || c == '_'
          j = i + 1
          while j < size && (chars[j].ascii_alphanumeric? || chars[j] == '_' || chars[j] == '.')
            j += 1
          end
          tokens << Token.new(Kind::Ident, chars[i...j].join, line)
          i = j
        elsif c.ascii_number?
          j = i + 1
          while j < size
            d = chars[j]
            if d.ascii_alphanumeric? || d == '.'
              j += 1
            elsif (d == '+' || d == '-') && (chars[j - 1] == 'e' || chars[j - 1] == 'E')
              j += 1
            else
              break
            end
          end
          tokens << Token.new(Kind::Number, chars[i...j].join, line)
          i = j
        elsif c == '"' || c == '\''
          j = string_end(chars, i)
          tokens << Token.new(Kind::Str, chars[i...j].join, line)
          i = j
        else
          tokens << Token.new(Kind::Punct, c.to_s, line)
          i += 1
        end
      end
      tokens
    end

    def self.parse(content : String) : Document
      Parser.new(tokenize(strip_comments(content))).parse
    end

    private class Parser
      @tokens : Array(Token)

      def initialize(@tokens : Array(Token))
      end

      def parse : Document
        includes = [] of String
        services = [] of Service
        pos = 0
        while pos < @tokens.size
          if ident?(pos, "include") && (path = @tokens[pos + 1]?) && path.kind.str?
            includes << unquote(path.text)
            pos += 2
          elsif ident?(pos, "service") && (service = parse_service(pos))
            services << service[0]
            pos = service[1]
          elsif punct?(pos, "{") || punct?(pos, "(") || punct?(pos, "[")
            # A struct/enum/union body, a const map or a stray annotation:
            # nothing in it declares a service, so step over it whole.
            pos = matching(pos) + 1
          else
            pos += 1
          end
        end
        Document.new(includes, services)
      end

      # `service Name [extends Base] { Function* } [annotations]`. Returns
      # the service and the index just past it, or nil when the tokens at
      # `pos` are not a service header (e.g. a field named `service`).
      private def parse_service(pos : Int32) : Tuple(Service, Int32)?
        name = @tokens[pos + 1]?
        return unless name && name.kind.ident?
        cur = pos + 2
        extends = nil
        if ident?(cur, "extends")
          base = @tokens[cur + 1]?
          return unless base && base.kind.ident?
          extends = base.text
          cur += 2
        end
        return unless punct?(cur, "{")
        close = matching(cur)
        functions = parse_functions(cur + 1, close)
        after = close + 1
        after = matching(after) + 1 if punct?(after, "(")
        {Service.new(name.text, extends, functions, @tokens[pos].line), after}
      end

      private def parse_functions(from : Int32, to : Int32) : Array(Function)
        functions = [] of Function
        pos = from
        while pos < to
          if separator?(pos)
            pos += 1
            next
          end
          if punct?(pos, "(")
            pos = matching(pos) + 1
            next
          end
          if parsed = parse_function(pos, to)
            functions << parsed[0]
            pos = parsed[1]
          else
            pos += 1
          end
        end
        functions
      end

      # `[oneway] Type name ( Field* ) [throws ( Field* )] [annotations]`
      private def parse_function(pos : Int32, limit : Int32) : Tuple(Function, Int32)?
        line = @tokens[pos].line
        oneway = false
        cur = pos
        while cur < limit && (token = @tokens[cur]) && token.kind.ident? && FUNCTION_QUALIFIERS.includes?(token.text)
          oneway = true if token.text == "oneway"
          cur += 1
        end
        type = parse_type(cur, limit)
        return unless type
        return_type, cur = type
        name = @tokens[cur]?
        return unless cur < limit && name && name.kind.ident?
        cur += 1
        return unless punct?(cur, "(")
        close = matching(cur)
        return if close >= limit
        args = parse_fields(cur + 1, close)
        cur = close + 1
        if ident?(cur, "throws") && punct?(cur + 1, "(")
          cur = matching(cur + 1) + 1
        end
        cur = matching(cur) + 1 if cur < limit && punct?(cur, "(")
        {Function.new(name.text, return_type, oneway, args, line), Math.min(cur, limit)}
      end

      # `[id :] [required|optional] Type name [= ConstValue] [annotations]`,
      # each optionally followed by `,` or `;`.
      private def parse_fields(from : Int32, to : Int32) : Array(Field)
        fields = [] of Field
        pos = from
        while pos < to
          if separator?(pos)
            pos += 1
            next
          end
          line = @tokens[pos].line
          cur = pos
          id = nil
          if @tokens[cur].kind.number? && punct?(cur + 1, ":")
            id = @tokens[cur].text
            cur += 2
          end
          requiredness = nil
          if ident?(cur, "required") || ident?(cur, "optional")
            requiredness = @tokens[cur].text
            cur += 1
          end
          type = parse_type(cur, to)
          name = type ? @tokens[type[1]]? : nil
          unless type && name && type[1] < to && name.kind.ident?
            pos += 1
            next
          end
          cur = type[1] + 1
          cur = skip_const_value(cur + 1, to) if cur < to && punct?(cur, "=")
          cur = matching(cur) + 1 if cur < to && punct?(cur, "(")
          fields << Field.new(id, requiredness, type[0], name.text, line)
          pos = cur
        end
        fields
      end

      # A base type, a named type or a container (`map<K, V>`, `list<T>`,
      # `set<T>`, with an optional `cpp_type "..."`). Type annotations right
      # after the type are skipped. Returns the rendered type and the index
      # just past it.
      private def parse_type(pos : Int32, limit : Int32) : Tuple(String, Int32)?
        token = @tokens[pos]?
        return unless pos < limit && token && token.kind.ident?
        return if token.text == "throws"
        text = token.text
        cur = pos + 1
        if ident?(cur, "cpp_type") && (lit = @tokens[cur + 1]?) && lit.kind.str?
          cur += 2
        end
        if punct?(cur, "<")
          close = matching_angle(cur, limit)
          return unless close
          text = String.build do |io|
            io << text
            previous = token
            (cur..close).each do |k|
              part = @tokens[k]
              io << ' ' if word?(previous) && (word?(part) || part.text == "(")
              io << part.text
              io << ' ' if part.text == "," || part.text == ":"
              previous = part
            end
          end
          cur = close + 1
        end
        cur = matching(cur) + 1 if cur < limit && punct?(cur, "(") && followed_by_name?(cur, limit)
        {text, cur}
      end

      # True when the parenthesised group at `pos` is a type annotation, i.e.
      # an identifier (the field or function name) follows it. Without this a
      # function's own argument list would be eaten as an annotation.
      private def followed_by_name?(pos : Int32, limit : Int32) : Bool
        after = matching(pos) + 1
        return false unless after < limit
        token = @tokens[after]
        token.kind.ident? && !(after + 1 < limit && punct?(after + 1, ":"))
      end

      private def skip_const_value(pos : Int32, limit : Int32) : Int32
        return pos unless pos < limit
        cur = pos
        cur += 1 if punct?(cur, "+") || punct?(cur, "-")
        return cur unless cur < limit
        if punct?(cur, "[") || punct?(cur, "{")
          matching(cur) + 1
        else
          cur + 1
        end
      end

      # Index of the token closing the bracket at `pos`, or the last token
      # when the bracket is never closed. String tokens are already whole, so
      # a bracket inside a literal never counts.
      private def matching(pos : Int32) : Int32
        open = @tokens[pos].text
        close = case open
                when "{" then "}"
                when "(" then ")"
                when "[" then "]"
                else          return pos
                end
        depth = 0
        cur = pos
        while cur < @tokens.size
          token = @tokens[cur]
          if token.kind.punct?
            if token.text == open
              depth += 1
            elsif token.text == close
              depth -= 1
              return cur if depth == 0
            end
          end
          cur += 1
        end
        @tokens.size - 1
      end

      private def matching_angle(pos : Int32, limit : Int32) : Int32?
        depth = 0
        cur = pos
        while cur < limit
          token = @tokens[cur]
          if token.kind.punct?
            case token.text
            when "<" then depth += 1
            when ">"
              depth -= 1
              return cur if depth == 0
            when "(", "{", "["
              cur = matching(cur)
            end
          end
          cur += 1
        end
        nil
      end

      private def word?(token : Token) : Bool
        !token.kind.punct?
      end

      private def ident?(pos : Int32, text : String) : Bool
        token = @tokens[pos]?
        !token.nil? && token.kind.ident? && token.text == text
      end

      private def punct?(pos : Int32, text : String) : Bool
        token = @tokens[pos]?
        !token.nil? && token.kind.punct? && token.text == text
      end

      private def separator?(pos : Int32) : Bool
        token = @tokens[pos]?
        !token.nil? && token.kind.punct? && SEPARATORS.includes?(token.text)
      end

      private def unquote(literal : String) : String
        return literal if literal.size < 2
        literal[1...-1]
      end
    end
  end
end
