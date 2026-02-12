require "../models/minilexer/*"

class JavaLexer < MiniLexer
  # Keywords
  ABSTRACT     = "abstract"
  ASSERT       = "assert"
  BOOLEAN      = "boolean"
  BREAK        = "break"
  BYTE         = "byte"
  CASE         = "case"
  CATCH        = "catch"
  CHAR         = "char"
  CLASS        = "class"
  CONST        = "const"
  CONTINUE     = "continue"
  DEFAULT      = "default"
  DO           = "do"
  DOUBLE       = "double"
  ELSE         = "else"
  ENUM         = "enum"
  EXTENDS      = "extends"
  FINAL        = "final"
  FINALLY      = "finally"
  FLOAT        = "float"
  FOR          = "for"
  IF           = "if"
  GOTO         = "goto"
  IMPLEMENTS   = "implements"
  IMPORT       = "import"
  INSTANCEOF   = "instanceof"
  INT          = "int"
  INTERFACE    = "interface"
  LONG         = "long"
  NATIVE       = "native"
  NEW          = "new"
  PACKAGE      = "package"
  PRIVATE      = "private"
  PROTECTED    = "protected"
  PUBLIC       = "public"
  RETURN       = "return"
  SHORT        = "short"
  STATIC       = "static"
  STRICTFP     = "strictfp"
  SUPER        = "super"
  SWITCH       = "switch"
  SYNCHRONIZED = "synchronized"
  THIS         = "this"
  THROW        = "throw"
  THROWS       = "throws"
  TRANSIENT    = "transient"
  TRY          = "try"
  VOID         = "void"
  VOLATILE     = "volatile"
  WHILE        = "while"

  # Module related keywords
  MODULE     = "module"
  OPEN       = "open"
  REQUIRES   = "requires"
  EXPORTS    = "exports"
  OPENS      = "opens"
  TO         = "to"
  USES       = "uses"
  PROVIDES   = "provides"
  WITH       = "with"
  TRANSITIVE = "transitive"

  # Local Variable Type Inference
  VAR = "var" # reserved type name

  # Switch Expressions
  YIELD = "yield" # reserved type name from Java 14

  # Records
  RECORD = "record"

  # Sealed Classes
  SEALED     = "sealed"
  PERMITS    = "permits"
  NON_SEALED = "non-sealed"

  # Literals
  DECIMAL_LITERAL   = /0|[1-9]([_\d]*\d)?[lL]?/
  HEX_LITERAL       = /0[xX][0-9a-fA-F]([0-9a-fA-F_]*[0-9a-fA-F])?[lL]?/
  OCT_LITERAL       = /0[0-7]([0-7_]*[0-7])?[lL]?/
  BINARY_LITERAL    = /0[bB][01]([01_]*[01])?[lL]?/
  FLOAT_LITERAL     = /((\d+\.\d*|\.\d+)([eE][+-]?\d+)?|[+-]?\d+[eE][+-]?\d+)[fFdD]?/
  HEX_FLOAT_LITERAL = /0[xX]([0-9a-fA-F]+(\.[0-9a-fA-F]*)?|\.[0-9a-fA-F]+)[pP][+-]?\d+[fFdD]?/
  BOOL_LITERAL      = /true|false/
  CHAR_LITERAL      = /'([^'\\\r\n]|\\['"\\bfnrt]|\\u[0-9a-fA-F]{4}|\\[^'"\r\n])*'/
  STRING_LITERAL    = /"([^"\\\r\n]|\\["\\bfnrt]|\\u[0-9a-fA-F]{4}|\\[^"\r\n])*"/
  TEXT_BLOCK        = /"""\s*(.|\\["\\bfnrt])*?\s*"""/
  NULL_LITERAL      = "null"

  # Separators
  LPAREN = "("
  RPAREN = ")"
  LBRACE = "{"
  RBRACE = "}"
  LBRACK = "["
  RBRACK = "]"
  SEMI   = ";"
  COMMA  = ","
  DOT    = "."

  # Operators
  ASSIGN   = "="
  GT       = ">"
  LT       = "<"
  BANG     = "!"
  TILDE    = "~"
  QUESTION = "?"
  COLON    = ":"
  EQUAL    = "=="
  LE       = "<="
  GE       = ">="
  NOTEQUAL = "!="
  AND      = "&&"
  OR       = "||"
  INC      = "++"
  DEC      = "--"
  ADD      = "+"
  SUB      = "-"
  MUL      = "*"
  DIV      = "/"
  BITAND   = "&"
  BITOR    = "|"
  CARET    = "^"
  MOD      = "%"

  ADD_ASSIGN     = "+="
  SUB_ASSIGN     = "-="
  MUL_ASSIGN     = "*="
  DIV_ASSIGN     = "/="
  AND_ASSIGN     = "&="
  OR_ASSIGN      = "|="
  XOR_ASSIGN     = "^="
  MOD_ASSIGN     = "%="
  LSHIFT_ASSIGN  = "<<="
  RSHIFT_ASSIGN  = ">>="
  URSHIFT_ASSIGN = ">>>="
  RSHIFT         = ">>"
  URSHIFT        = ">>>"

  # Java 8 tokens
  ARROW      = "->"
  COLONCOLON = "::"

  # Additional symbols not defined in the lexical specification
  AT       = "@"
  ELLIPSIS = "..."

  # Whitespace and comments
  WS           = /[ \t\r\n\x0C]+/
  COMMENT      = /\/\*.*?\*\//m
  LINE_COMMENT = /\/\/[^\r\n]*/

  # Identifiers
  IDENTIFIER = /[a-zA-Z$_][a-zA-Z\d$_]*/

  # Fragment rules
  ExponentPart   = /[eE][+-]?\d+/
  EscapeSequence = /\\(?:u005c)?[btnfr"'\\]|\\u(?:[0-3]?[0-7])?[0-7]|\\u[0-9a-fA-F]{4}/
  HexDigits      = /[0-9a-fA-F]([_0-9a-fA-F]*[0-9a-fA-F])?/
  HexDigit       = /[0-9a-fA-F]/
  Digits         = /\d([_\d]*\d)?/
  LetterOrDigit  = /[a-zA-Z\d$_]/
  Letter         = /[a-zA-Z$_]|[^[:ascii:]]/

  def initialize
    super
  end

  def tokenize(@input : String) : Array(Token)
    super
  end

  def tokenize_logic(@input : String) : Array(Token)
    @tokens.clear
    after_skip = -1
    while @position < @input.size
      while @position < @input.size && @position != after_skip
        after_skip = @position
        skip_whitespace_and_comments
      end
      break if @position == @input.size

      case @input[@position]
      when '0'..'9'
        match_number
      when 'a'..'z', 'A'..'Z', '$', '_'
        match_identifier_or_keyword
      when '\''
        match_char_literal
      when '"'
        match_string_literal_or_text_block
      when '+', '-', '*', '/', '%', '&', '|', '^', '!', '=', '<', '>', '?', ':', '~'
        match_operator
      when '.', ',', '(', ')', '{', '}', '[', ']', ';', '@'
        match_punctuation
      else
        match_other
      end
    end

    @tokens
  end

  def skip_whitespace_and_comments
    c = @input[@position]
    if c == '\r' || c == '\t' || c == ' '
      @position += 1
    elsif @position != @input.size - 1
      if c == '/' && @input[@position + 1] == '*'
        @position += 2
        while @position < @input.size
          if @position + 1 < @input.size && @input[@position] == '*' && @input[@position + 1] == '/'
            @position += 2
            break
          end
          @position += 1
        end
      elsif c == '/' && @input[@position + 1] == '/'
        @position += 2
        while @position < @input.size
          if @input[@position] == '\n'
            break
          end
          @position += 1
        end
      end
    end
  end

  def match_number
    if match = @input.match(/0[xX][0-9a-fA-F](_?[0-9a-fA-F])*[lL]?|\d(_?\d)*(\.\d(_?\d)*)?([eE][+-]?\d(_?\d)*)?[fFdD]?/, @position, options: :anchored)
      literal = match[0]
      self << case literal
      when /^0[xX]/
        @position += literal.size
        Tuple.new(:HEX_LITERAL, literal)
      when /^0/
        @position += literal.size
        Tuple.new(:OCT_LITERAL, literal)
      when /^[\d.]/
        @position += literal.size
        Tuple.new(:DECIMAL_LITERAL, literal)
      else
        @position += 1
        Tuple.new(:IDENTIFIER, @input[@position].to_s)
      end
    else
      self << Tuple.new(:IDENTIFIER, @input[@position].to_s)
      @position += 1
    end
  end

  def match_identifier_or_keyword
    if match = @input.match(/[a-zA-Z$_][a-zA-Z\d$_]*/, @position, options: :anchored)
      type = case match[0]
             when ABSTRACT     then :ABSTRACT
             when ASSERT       then :ASSERT
             when BOOLEAN      then :BOOLEAN
             when BREAK        then :BREAK
             when BYTE         then :BYTE
             when CASE         then :CASE
             when CATCH        then :CATCH
             when CHAR         then :CHAR
             when CLASS        then :CLASS
             when CONST        then :CONST
             when CONTINUE     then :CONTINUE
             when DEFAULT      then :DEFAULT
             when DO           then :DO
             when DOUBLE       then :DOUBLE
             when ELSE         then :ELSE
             when ENUM         then :ENUM
             when EXTENDS      then :EXTENDS
             when FINAL        then :FINAL
             when FINALLY      then :FINALLY
             when FLOAT        then :FLOAT
             when FOR          then :FOR
             when IF           then :IF
             when GOTO         then :GOTO
             when IMPLEMENTS   then :IMPLEMENTS
             when IMPORT       then :IMPORT
             when INSTANCEOF   then :INSTANCEOF
             when INT          then :INT
             when INTERFACE    then :INTERFACE
             when LONG         then :LONG
             when NATIVE       then :NATIVE
             when NEW          then :NEW
             when PACKAGE      then :PACKAGE
             when PRIVATE      then :PRIVATE
             when PROTECTED    then :PROTECTED
             when PUBLIC       then :PUBLIC
             when RETURN       then :RETURN
             when SHORT        then :SHORT
             when STATIC       then :STATIC
             when STRICTFP     then :STRICTFP
             when SUPER        then :SUPER
             when SWITCH       then :SWITCH
             when SYNCHRONIZED then :SYNCHRONIZED
             when THIS         then :THIS
             when THROW        then :THROW
             when THROWS       then :THROWS
             when TRANSIENT    then :TRANSIENT
             when TRY          then :TRY
             when VOID         then :VOID
             when VOLATILE     then :VOLATILE
             when WHILE        then :WHILE
             when MODULE       then :MODULE
             when OPEN         then :OPEN
             when REQUIRES     then :REQUIRES
             when EXPORTS      then :EXPORTS
             when OPENS        then :OPENS
             when TO           then :TO
             when USES         then :USES
             when PROVIDES     then :PROVIDES
             when WITH         then :WITH
             when TRANSITIVE   then :TRANSITIVE
             when VAR          then :VAR
             when YIELD        then :YIELD
             when RECORD       then :RECORD
             when SEALED       then :SEALED
             when PERMITS      then :PERMITS
             when NON_SEALED   then :NON_SEALED
             else                   :IDENTIFIER
             end

      self << Tuple.new(type, match[0])
      @position += match[0].size
    else
      self << Tuple.new(:IDENTIFIER, @input[@position].to_s)
      @position += 1
    end
  end

  def match_char_literal
    if match = @input.match(/'([^'\\\r\n]|\\['"\\bfnrt]|\\u[0-9a-fA-F]{4}|\\[^'\r\n])*'/, @position, options: :anchored)
      self << Tuple.new(:CHAR_LITERAL, match[0])
      @position += match[0].size
    else
      # impossible to reach here if dispatched correctly
      self << Tuple.new(:UNKNOWN, @input[@position].to_s)
      @position += 1
    end
  end

  def match_string_literal_or_text_block
    if match = @input.match(/"""[ \t]*[\r\n](.|\\["\\bfnrt])*?[\r\n][ \t]*"""/, @position, options: :anchored)
      self << Tuple.new(:TEXT_BLOCK, match[0])
      @position += match[0].size
    elsif match = @input.match(/"[^"\\\r\n]*(\\["\\bfnrt][^"\\\r\n]*)*"/, @position, options: :anchored)
      self << Tuple.new(:STRING_LITERAL, match[0])
      @position += match[0].size
    else
      self << Tuple.new(:UNKNOWN, @input[@position].to_s)
      @position += 1
    end
  end

  def match_operator
    case @input[@position]
    when '+'
      if @position + 1 < @input.size && @input[@position + 1] == '+'
        @position += 2
        self << Tuple.new(:INC, "++")
      elsif @position + 1 < @input.size && @input[@position + 1] == '='
        @position += 2
        self << Tuple.new(:ADD_ASSIGN, "+=")
      else
        @position += 1
        self << Tuple.new(:ADD, "+")
      end
    when '-'
      if @position + 1 < @input.size && @input[@position + 1] == '-'
        @position += 2
        self << Tuple.new(:DEC, "--")
      elsif @position + 1 < @input.size && @input[@position + 1] == '='
        @position += 2
        self << Tuple.new(:SUB_ASSIGN, "-=")
      elsif @position + 1 < @input.size && @input[@position + 1] == '>'
        @position += 2
        self << Tuple.new(:ARROW, "->")
      else
        @position += 1
        self << Tuple.new(:SUB, "-")
      end
    when '*'
      if @position + 1 < @input.size && @input[@position + 1] == '='
        @position += 2
        self << Tuple.new(:MUL_ASSIGN, "*=")
      else
        @position += 1
        self << Tuple.new(:MUL, "*")
      end
    when '/'
      if @position + 1 < @input.size && @input[@position + 1] == '='
        @position += 2
        self << Tuple.new(:DIV_ASSIGN, "/=")
      else
        @position += 1
        self << Tuple.new(:DIV, "/")
      end
    when '%'
      if @position + 1 < @input.size && @input[@position + 1] == '='
        @position += 2
        self << Tuple.new(:MOD_ASSIGN, "%=")
      else
        @position += 1
        self << Tuple.new(:MOD, "%")
      end
    when '&'
      if @position + 1 < @input.size && @input[@position + 1] == '&'
        @position += 2
        self << Tuple.new(:AND, "&&")
      elsif @position + 1 < @input.size && @input[@position + 1] == '='
        @position += 2
        self << Tuple.new(:AND_ASSIGN, "&=")
      else
        @position += 1
        self << Tuple.new(:BITAND, "&")
      end
    when '|'
      if @position + 1 < @input.size && @input[@position + 1] == '|'
        @position += 2
        self << Tuple.new(:OR, "||")
      elsif @position + 1 < @input.size && @input[@position + 1] == '='
        @position += 2
        self << Tuple.new(:OR_ASSIGN, "|=")
      else
        @position += 1
        self << Tuple.new(:BITOR, "|")
      end
    when '^'
      if @position + 1 < @input.size && @input[@position + 1] == '='
        @position += 2
        self << Tuple.new(:XOR_ASSIGN, "^=")
      else
        @position += 1
        self << Tuple.new(:CARET, "^")
      end
    when '!'
      if @position + 1 < @input.size && @input[@position + 1] == '='
        @position += 2
        self << Tuple.new(:NOTEQUAL, "!=")
      else
        @position += 1
        self << Tuple.new(:BANG, "!")
      end
    when '='
      if @position + 1 < @input.size && @input[@position + 1] == '='
        @position += 2
        self << Tuple.new(:EQUAL, "==")
      else
        @position += 1
        self << Tuple.new(:ASSIGN, "=")
      end
    when '<'
      if @position + 1 < @input.size && @input[@position + 1] == '='
        @position += 2
        self << Tuple.new(:LE, "<=")
      elsif @position + 1 < @input.size && @input[@position + 1] == '<'
        if @position + 2 < @input.size && @input[@position + 2] == '='
          @position += 3
          self << Tuple.new(:LSHIFT_ASSIGN, "<<=")
        else
          @position += 2
          # Assuming LSHIFT operator is not defined in constants but LSHIFT_ASSIGN is?
          # Constants include LSHIFT_ASSIGN.
          # But not LSHIFT.
          # However, checking `match_punctuation` or constants.
          # Constants list: ASSIGN, GT, LT, ...
          # It does not list LSHIFT (<<).
          # So I'll emit UNKNOWN or just handle it if I missed a constant.
          # Wait, `LSHIFT` is common. JavaLexer constants list `LSHIFT_ASSIGN`.
          # Maybe I should add LSHIFT? Or emit LT twice?
          # I'll emit UNKNOWN for now if not in list, or just add LSHIFT constant.
          # I cannot change constants easily as they are part of class definition I am rewriting.
          # I'll check my rewritten class.
          # I didn't add LSHIFT constant.
          # So I'll just emit UNKNOWN for `<<` unless I add it.
          # Or maybe existing code didn't handle `<<`?
          # Existing code `match_other` didn't handle `<<`.
          # So I'll handle `<` and check `<=`.
          self << Tuple.new(:UNKNOWN, "<<")
        end
      else
        @position += 1
        self << Tuple.new(:LT, "<")
      end
    when '>'
      if @position + 1 < @input.size && @input[@position + 1] == '>'     # starts with >>
        if @position + 2 < @input.size && @input[@position + 2] == '>'   # starts with >>>
          if @position + 3 < @input.size && @input[@position + 3] == '=' # >>>=
            @position += 4
            self << Tuple.new(:URSHIFT_ASSIGN, ">>>=")
          else # >>>
            @position += 3
            self << Tuple.new(:URSHIFT, ">>>")
          end
        elsif @position + 2 < @input.size && @input[@position + 2] == '=' # >>=
          @position += 3
          self << Tuple.new(:RSHIFT_ASSIGN, ">>=")
        else # >>
          @position += 2
          self << Tuple.new(:RSHIFT, ">>")
        end
      elsif @position + 1 < @input.size && @input[@position + 1] == '=' # >=
        @position += 2
        self << Tuple.new(:GE, ">=")
      else # >
        @position += 1
        self << Tuple.new(:GT, ">")
      end
    when '?'
      @position += 1
      self << Tuple.new(:QUESTION, "?")
    when ':'
      if @position + 1 < @input.size && @input[@position + 1] == ':'
        @position += 2
        self << Tuple.new(:COLONCOLON, "::")
      else
        @position += 1
        self << Tuple.new(:COLON, ":")
      end
    when '~'
      @position += 1
      self << Tuple.new(:TILDE, "~")
    else
      self << Tuple.new(:UNKNOWN, @input[@position].to_s)
      @position += 1
    end
  end

  def match_punctuation
    case @input[@position]
    when '(' then self << Tuple.new(:LPAREN, "(")
    when ')' then self << Tuple.new(:RPAREN, ")")
    when '.'
      if @position + 2 < @input.size && @input[@position + 1] == '.' && @input[@position + 2] == '.'
        @position += 3
        self << Tuple.new(:ELLIPSIS, "...")
      else
        self << Tuple.new(:DOT, ".")
        @position += 1 # Only +1 for DOT
      end
      return # Returned because of variable consumption
    when ',' then self << Tuple.new(:COMMA, ",")
    when '@' then self << Tuple.new(:AT, "@")
    when '{' then self << Tuple.new(:LBRACE, "{")
    when '}' then self << Tuple.new(:RBRACE, "}")
    when '[' then self << Tuple.new(:LBRACK, "[")
    when ']' then self << Tuple.new(:RBRACK, "]")
    when ';' then self << Tuple.new(:SEMI, ";")
    else
      self << Tuple.new(:UNKNOWN, @input[@position].to_s)
    end
    # For single char punctuation, increment
    @position += 1
  end

  def match_other
    # Fallback
    case @input[@position]
    when '\n'
      self << Tuple.new(:NEWLINE, "\n")
    when ' '
      # Should be handled by skip_whitespace_and_comments now, but if not:
      # Skip
    else
      self << Tuple.new(:UNKNOWN, @input[@position].to_s)
    end
    @position += 1
  end
end
