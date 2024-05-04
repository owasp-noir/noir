require "../models/minilexer/*"

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

class JavaLexer < MiniLexer
  def initialize
    super
  end

  def tokenize(@input : String) : Array(Token)
    super
  end

  def tokenize_logic(@input : String) : Array(Token)
    after_skip = -1
    while @position < @input.size
      while @position != after_skip
        skip_whitespace_and_comments
        after_skip = @position
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
      else
        match_other
      end
    end

    @tokens
  end

  def skip_whitespace_and_comments
    c = @input[@position]
    if c == '\r' || c == '\t'
      @position += 1
    elsif @position != @input.size - 1
      if c == '/' && @input[@position + 1] == '*'
        @position += 2
        while @position < @input.size
          if @input[@position] == '*' && @input[@position + 1] == '/'
            @position += 2
            break
          end
          @position += 1
        end
      elsif c == '/' && @input[@position + 1] == '/'
        @position += 2
        while @position < @input.size
          if @input[@position] == '\n'
            @position += 1
            break
          end
          @position += 1
        end
      end
    end
  end

  def match_number
    if match = @input.match(/0[xX][0-9a-fA-F](_?[0-9a-fA-F])*[lL]?|\d(_?\d)*(\.\d(_?\d)*)?([eE][+-]?\d(_?\d)*)?[fFdD]?/, @position)
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
    if match = @input.match(/[a-zA-Z$_][a-zA-Z\d$_]*/, @position)
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
    if match = @input.match(/'([^'\\\r\n]|\\['"\\bfnrt]|\\u[0-9a-fA-F]{4}|\\[^'\r\n])*'/, @position)
      self << Tuple.new(:CHAR_LITERAL, match[0])
      @position += match[0].size
    else
      # impossible to reach here
      self << Tuple.new(:UNKNOWN, @input[@position].to_s)
      @position += 1
    end
  end

  def match_string_literal_or_text_block
    if match = @input.match(/"""[ \t]*[\r\n](.|\\["\\bfnrt])*?[\r\n][ \t]*"""/, @position)
      self << Tuple.new(:TEXT_BLOCK, match[0])
      @position += match[0].size
    elsif match = @input.match(/"[^"\\\r\n]*(\\["\\bfnrt][^"\\\r\n]*)*"/, @position)
      self << Tuple.new(:STRING_LITERAL, match[0])
      @position += match[0].size
    else
      # impossible to reach here
      self << Tuple.new(:UNKNOWN, @input[@position].to_s)
      @position += 1
    end
  end

  def match_other
    case @input[@position]
    when '('  then self << Tuple.new(:LPAREN, "(")
    when ')'  then self << Tuple.new(:RPAREN, ")")
    when '.'  then self << Tuple.new(:DOT, ".")
    when ','  then self << Tuple.new(:COMMA, ",")
    when '@'  then self << Tuple.new(:AT, "@")
    when '{'  then self << Tuple.new(:LBRACE, "{")
    when '}'  then self << Tuple.new(:RBRACE, "}")
    when ';'  then self << Tuple.new(:SEMI, ";")
    when '='
      if @input[@position + 1] == '='
        @position += 1
        Tuple.new(:EQUAL, "==")
      else
        Tuple.new(:ASSIGN, "=")
      end
    when '\t' then self << Tuple.new(:TAB, "\t")
    when '\n'
      self << Tuple.new(:NEWLINE, "\n")
    when ' '
      # Skipping whitespace for efficiency
    else
      self << Tuple.new(:UNKNOWN, @input[@position].to_s)
    end
    @position += 1
  end
end
