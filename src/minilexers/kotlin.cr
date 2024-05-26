require "../models/minilexer/*"

class KotlinLexer < MiniLexer
  KEYWORDS = {
    "file" => :FILE, "package" => :PACKAGE, "import" => :IMPORT, "class" => :CLASS,
    "interface" => :INTERFACE, "fun" => :FUN, "object" => :OBJECT, "val" => :VAL,
    "var" => :VAR, "typealias" => :TYPE_ALIAS, "constructor" => :CONSTRUCTOR, "by" => :BY,
    "companion" => :COMPANION, "init" => :INIT, "this" => :THIS, "super" => :SUPER,
    "typeof" => :TYPEOF, "where" => :WHERE, "if" => :IF, "else" => :ELSE, "when" => :WHEN,
    "try" => :TRY, "catch" => :CATCH, "finally" => :FINALLY, "for" => :FOR, "do" => :DO,
    "while" => :WHILE, "throw" => :THROW, "return" => :RETURN, "continue" => :CONTINUE,
    "break" => :BREAK, "as" => :AS, "is" => :IS, "in" => :IN, "out" => :OUT,
    "public" => :PUBLIC, "private" => :PRIVATE, "protected" => :PROTECTED, "internal" => :INTERNAL,
    "enum" => :ENUM, "sealed" => :SEALED, "annotation" => :ANNOTATION, "data" => :DATA,
    "inner" => :INNER, "tailrec" => :TAILREC, "operator" => :OPERATOR, "inline" => :INLINE,
    "infix" => :INFIX, "external" => :EXTERNAL, "suspend" => :SUSPEND, "override" => :OVERRIDE,
    "abstract" => :ABSTRACT, "final" => :FINAL, "open" => :OPEN, "const" => :CONST,
    "lateinit" => :LATEINIT, "vararg" => :VARARG, "noinline" => :NOINLINE,
    "crossinline" => :CROSSINLINE, "reified" => :REIFIED,
  }

  ANNOTATIONS = {
    "@field"    => :FIELD,
    "@property" => :PROPERTY,
    "@get"      => :GET,
    "@set"      => :SET,
    "@receiver" => :RECEIVER,
    "@param"    => :PARAM,
    "@setparam" => :SETPARAM,
    "@delegate" => :DELEGATE,
  }

  PUNCTUATION = {
    '.' => :DOT, ',' => :COMMA, '(' => :LPAREN, ')' => :RPAREN,
    '{' => :LCURL, '}' => :RCURL, '[' => :LSQUARE, ']' => :RSQUARE,
    ';' => :SEMI, ':' => :COLON, '?' => :QUESTION,
  }

  OPERATORS = {
    '+' => :ADD, '-' => :SUB, '*' => :MULT, '/' => :DIV, '%' => :MOD,
    '=' => :ASSIGN, "==" => :EQUAL, "!=" => :NOTEQUAL, '>' => :RANGLE, '<' => :LANGLE,
    ">=" => :GE, "<=" => :LE, "&&" => :AND, "||" => :OR, '!' => :BANG,
    "++" => :INC, "--" => :DEC, "+=" => :ADD_ASSIGN, "-=" => :SUB_ASSIGN,
    "*=" => :MUL_ASSIGN, "/=" => :DIV_ASSIGN, "%=" => :MOD_ASSIGN,
    '&' => :BITAND, '|' => :BITOR, '^' => :CARET, '~' => :TILDE,
    "->" => :ARROW, "=>" => :DOUBLE_ARROW, "?:" => :ELVIS,
  }

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
      when 'a'..'z', 'A'..'Z', '_'
        match_identifier_or_keyword
      when '@'
        match_annotation
      when '"', '\''
        match_string_or_char_literal
      when '.', ',', '(', ')', '{', '}', '[', ']', ';', '?', ':'
        match_punctuation
      when '+', '-', '*', '/', '%', '&', '|', '^', '!', '=', '<', '>', '~'
        match_operator
      else
        match_other
      end
    end

    @tokens
  end

  private def skip_whitespace_and_comments
    while @position < @input.size
      case @input[@position]
      when ' ', '\t', '\r'
        @position += 1
      when '/'
        if @position + 1 < @input.size
          case @input[@position + 1]
          when '/'
            # Skip single line comment
            @position += 2
            while @position < @input.size && @input[@position] != '\n'
              @position += 1
            end
          when '*'
            # Skip multi-line comment
            @position += 2
            while @position + 1 < @input.size
              if @input[@position] == '*' && @input[@position + 1] == '/'
                @position += 2
                break
              end
              @position += 1
            end
          else
            break
          end
        else
          break
        end
      else
        break
      end
    end
  end

  private def match_number
    if match = @input.match(/\d+(_\d+)*\.?\d*([eE][+-]?\d+)?/, @position)
      type = match[0].includes?('.') ? :FLOAT_LITERAL : :INTEGER_LITERAL
      self << Tuple.new(type, match[0])
      @position += match[0].size
    else
      self << Tuple.new(:UNKNOWN, @input[@position])
      @position += 1
    end
  end

  private def match_identifier_or_keyword
    if match = @input.match(/[a-zA-Z_][a-zA-Z0-9_]*/, @position)
      type = KEYWORDS[match[0]]? || :IDENTIFIER
      self << Tuple.new(type, match[0])
      @position += match[0].size
    else
      self << Tuple.new(:UNKNOWN, @input[@position])
      @position += 1
    end
  end

  private def match_annotation
    if match = @input.match(/\@[a-zA-Z_][a-zA-Z0-9_]*/, @position)
      type = KotlinLexer::ANNOTATIONS[match[0]]? || :ANNOTATION
      self << Tuple.new(type, match[0])
      @position += match[0].size
    else
      self << Tuple.new(:UNKNOWN, @input[@position])
      @position += 1
    end
  end

  private def match_string_or_char_literal
    s = @input[@position].to_s

    text_block_literal = "\"\"\""
    if @position < @input.size - 3 && @input[@position..@position + 2] == text_block_literal
      s = text_block_literal
      @position += 3
      while @position < @input.size - 3
        s += @input[@position]
        if @input[@position..@position + 2] == text_block_literal
          s += "\"\""
          break
        end
        @position += 1
      end

      if s.starts_with?(text_block_literal) && s.ends_with?(text_block_literal)
        self << Tuple.new(:TEXT_BLOCK, s)
        @position += 3
        return
      end
    else
      @position += 1
      is_backslash_char = false
      while @position < @input.size
        s += @input[@position]
        break if !is_backslash_char && @input[@position] == s[0]
        is_backslash_char = s[0] == '\\'
        @position += 1
      end

      if s.size > 1
        if s[0] == '\'' && s[-1] == '\''
          self << Tuple.new(:CHAR_LITERAL, s)
          @position += 1
          return
        elsif s[0] == '"' && s[-1] == '"'
          self << Tuple.new(:STRING_LITERAL, s)
          @position += 1
          return
        end
      end
    end
  end

  private def match_punctuation
    char = @input[@position]
    type = PUNCTUATION[char]? || :UNKNOWN
    self << Tuple.new(type, char)
    @position += 1
  end

  private def match_operator
    # Match longer operators first by checking next characters
    if @position + 1 < @input.size && OPERATORS.has_key?(@input[@position..@position + 1])
      op = @input[@position..@position + 1]
      @position += 2
    elsif OPERATORS.has_key?(@input[@position])
      op = @input[@position]
      @position += 1
    else
      op = nil
    end

    if op
      type = OPERATORS[op]
      self << Tuple.new(type, op)
    else
      # Handle the case where the operator is unknown
      self << Tuple.new(:UNKNOWN, @input[@position])
      @position += 1
    end
  end

  def match_other
    case @input[@position]
    when '\t'
      self << Tuple.new(:TAB, "\t")
    when '\n'
      self << Tuple.new(:NEWLINE, "\n")
    when '@'
      self << Tuple.new(:AT, '@')
    when ' '
      # Skipping whitespace for efficiency
    else
      self << Tuple.new(:UNKNOWN, @input[@position].to_s)
    end
    @position += 1
  end
end
