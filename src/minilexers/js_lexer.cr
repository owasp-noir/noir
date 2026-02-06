module Noir
  # MiniToken represents a simple token in JavaScript code
  class JSToken
    getter type : Symbol
    getter value : String
    getter position : Int32

    def initialize(@type : Symbol, @value : String, @position : Int32)
    end

    def to_s
      "#{@type}(#{@value})"
    end
  end

  # JSLexer is a simple JavaScript lexer for route detection
  class JSLexer
    @source : String
    @position : Int32 = 0
    @current_char : Char = '\0'
    @tokens : Array(JSToken) = [] of JSToken

    def initialize(@source : String)
      @current_char = @source[@position]? || '\0'
    end

    def tokenize : Array(JSToken)
      @tokens.clear

      while @current_char != '\0'
        case @current_char
        when .whitespace?
          skip_whitespace
        when '('
          add_token(:lparen, "(")
          advance
        when ')'
          add_token(:rparen, ")")
          advance
        when '{'
          add_token(:lbrace, "{")
          advance
        when '}'
          add_token(:rbrace, "}")
          advance
        when '['
          add_token(:lbracket, "[")
          advance
        when ']'
          add_token(:rbracket, "]")
          advance
        when ','
          add_token(:comma, ",")
          advance
        when ':'
          add_token(:colon, ":")
          advance
        when ';'
          add_token(:semicolon, ";")
          advance
        when '.'
          add_token(:dot, ".")
          advance
        when '"', '\''
          tokenize_string
        when '`'
          tokenize_template_literal
        when '+'
          add_token(:plus, "+")
          advance
        when '/'
          if peek == '/' # Single line comment
            skip_line_comment
          elsif peek == '*' # Multi line comment
            skip_multiline_comment
          elsif looks_like_regex? # Regex literal
            tokenize_regex
          else
            add_token(:operator, "/")
            advance
          end
        when '0'..'9'
          tokenize_number
        when 'a'..'z', 'A'..'Z', '_', '$'
          tokenize_identifier
        else
          add_token(:unknown, @current_char.to_s)
          advance
        end
      end

      @tokens
    end

    private def add_token(type : Symbol, value : String)
      @tokens << JSToken.new(type, value, @position - value.size)
    end

    private def advance
      @position += 1
      @current_char = @source[@position]? || '\0'
    end

    private def peek
      @source[@position + 1]? || '\0'
    end

    private def skip_whitespace
      while @current_char.whitespace? && @current_char != '\0'
        advance
      end
    end

    private def skip_line_comment
      # Skip the //
      advance
      advance

      # Skip until end of line or end of file
      while @current_char != '\n' && @current_char != '\0'
        advance
      end
    end

    private def skip_multiline_comment
      # Skip the /*
      advance
      advance

      # Skip until */ or end of file
      while !(@current_char == '*' && peek == '/') && @current_char != '\0'
        advance
      end

      # Skip the */
      if @current_char != '\0'
        advance
        advance
      end
    end

    private def tokenize_string
      quote_char = @current_char
      # start_pos = @position
      advance # Skip the opening quote

      string_value = ""
      while @current_char != quote_char && @current_char != '\0'
        # Handle escape sequences
        if @current_char == '\\' && (peek == quote_char || peek == '\\')
          advance
        end

        string_value += @current_char
        advance
      end

      # Skip the closing quote
      advance if @current_char == quote_char

      add_token(:string, string_value)
    end

    private def tokenize_number
      number = ""

      while '0' <= @current_char <= '9' || @current_char == '.'
        number += @current_char
        advance
      end

      add_token(:number, number)
    end

    private def tokenize_template_literal
      advance # Skip the opening backtick

      template_value = ""
      while @current_char != '`' && @current_char != '\0'
        # Handle escape sequences
        if @current_char == '\\' && (peek == '`' || peek == '\\')
          advance
        end

        template_value += @current_char
        advance
      end

      # Skip the closing backtick
      advance if @current_char == '`'

      add_token(:template_literal, template_value)
    end

    private def tokenize_identifier
      identifier = ""

      while ('a' <= @current_char <= 'z') ||
            ('A' <= @current_char <= 'Z') ||
            ('0' <= @current_char <= '9') ||
            @current_char == '_' ||
            @current_char == '$'
        identifier += @current_char
        advance
      end

      # Check if it's a keyword
      case identifier
      when "function", "async", "const", "let", "var", "return", "if", "else", "for", "while"
        add_token(:keyword, identifier)
      when "true", "false", "null", "undefined"
        add_token(:literal, identifier)
      else
        # Check for HTTP methods case-insensitively
        lower_identifier = identifier.downcase
        if lower_identifier == "get" || lower_identifier == "post" || lower_identifier == "put" ||
           lower_identifier == "delete" || lower_identifier == "options" || lower_identifier == "head" ||
           lower_identifier == "patch" || lower_identifier == "del" || lower_identifier == "all"
          add_token(:http_method, identifier)
        else
          add_token(:identifier, identifier)
        end
      end
    end

    # Heuristic to determine if '/' starts a regex literal
    private def looks_like_regex? : Bool
      # Heuristic: regex if preceded by ( , = [ or http_method token
      return false if @tokens.empty?

      last_token = @tokens.last
      return true if last_token.type == :lparen
      return true if last_token.type == :comma
      return true if last_token.value == "="
      return true if last_token.type == :http_method
      return true if last_token.type == :lbracket

      false
    end

    # Tokenize a regex literal
    private def tokenize_regex
      advance # Skip opening /

      regex_pattern = ""
      while @current_char != '/' && @current_char != '\0'
        if @current_char == '\\'  # Handle escape sequences
          regex_pattern += @current_char
          advance
          regex_pattern += @current_char if @current_char != '\0'
          advance
        else
          regex_pattern += @current_char
          advance
        end
      end

      advance if @current_char == '/'  # Skip closing /

      # Read regex flags (g, i, m, s, u, y)
      regex_flags = ""
      while @current_char == 'g' || @current_char == 'i' ||
            @current_char == 'm' || @current_char == 's' ||
            @current_char == 'u' || @current_char == 'y'
        regex_flags += @current_char
        advance
      end

      # Store pattern and flags separately to preserve regex form
      add_token(:regex, "#{regex_pattern}\n#{regex_flags}")
    end
  end
end
