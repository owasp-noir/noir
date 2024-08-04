require "../models/minilexer/*"

class PythonLexer < MiniLexer
    # Python Keywords
    # Regular Expressions for Tokens
    IDENTIFIER = /^[a-zA-Z_]\w*/ # Unsupport unicode characters for now

    # Token Definitions
    PUNCTUATION = {
        '.' => :DOT, ',' => :COMMA, '(' => :LPAREN, ')' => :RPAREN,
        '{' => :LCURL, '}' => :RCURL, '[' => :LSQUARE, ']' => :RSQUARE,
        ';' => :SEMI, ':' => :COLON, '?' => :QUESTION,
    }

    # https://docs.python.org/3.12/reference/lexical_analysis.html#keywords
    KEYWORDS = {
        "False"    => :FALSE,
        "await"    => :AWAIT,
        "else"     => :ELSE,
        "import"   => :IMPORT,
        "pass"     => :PASS,
        "None"     => :NONE,
        "break"    => :BREAK,
        "except"   => :EXCEPT,
        "in"       => :IN,
        "raise"    => :RAISE,
        "True"     => :TRUE,
        "class"    => :CLASS,
        "finally"  => :FINALLY,
        "is"       => :IS,
        "return"   => :RETURN,
        "and"      => :AND,
        "continue" => :CONTINUE,
        "for"      => :FOR,
        "lambda"   => :LAMBDA,
        "try"      => :TRY,
        "as"       => :AS,
        "def"      => :DEF,
        "from"     => :FROM,
        "nonlocal" => :NONLOCAL,
        "while"    => :WHILE,
        "assert"   => :ASSERT,
        "del"      => :DEL,
        "global"   => :GLOBAL,
        "not"      => :NOT,
        "with"     => :WITH,
        "async"    => :ASYNC,
        "elif"     => :ELIF,
        "if"       => :IF,
        "or"       => :OR,
        "yield"    => :YIELD,
    }

    # https://docs.python.org/3.12/library/token.html#module-token
    OPERATORS = {
        '+' => :ADD, '-' => :SUB, '*' => :MULT, '/' => :DIV, '%' => :MOD,
        '=' => :ASSIGN, "==" => :EQUAL, "!=" => :NOTEQUAL, '>' => :RANGLE, '<' => :LANGLE,
        ">=" => :GE, "<=" => :LE, "&&" => :AND, "||" => :OR, '!' => :BANG,
        "++" => :INC, "--" => :DEC, "+=" => :ADD_ASSIGN, "-=" => :SUB_ASSIGN,
        "*=" => :MUL_ASSIGN, "/=" => :DIV_ASSIGN, "%=" => :MOD_ASSIGN,
        '&' => :BITAND, '|' => :BITOR, '^' => :CARET, '~' => :TILDE,
        "->" => :ARROW, "=>" => :DOUBLE_ARROW, "?:" => :ELVIS,
        "<<" => :LEFTSHIFT, ">>" => :RIGHTSHIFT, "**" => :DOUBLESTAR,
        "+=" => :PLUSEQUAL, "-=" => :MINEQUAL, "*=" => :STAREQUAL,
        "/=" => :SLASHEQUAL, "%=" => :PERCENTEQUAL, "&=" => :AMPEREQUAL,
        "|=" => :VBAREQUAL, "^=" => :CIRCUMFLEXEQUAL, "<<=" => :LEFTSHIFTEQUAL,
        ">>=" => :RIGHTSHIFTEQUAL, "**=" => :DOUBLESTAREQUAL, "//" => :DOUBLESLASH,
        "//=" => :DOUBLESLASHEQUAL, "@" => :AT, "@=" => :ATEQUAL,
        "->" => :RARROW, "..." => :ELLIPSIS, ":=" => :COLONEQUAL,
        "!" => :EXCLAMATION,
    }

    def initialize
        super
    end

    def tokenize_logic(@input : String) : Array(Token)
        @tokens.clear
        while @position < @input.size
            case @input[@position]
            when '\n'
                match_newline
                match_indentation
            when '#'
                match_comment
            when '0'..'9'
                match_number
            when '"', '\'', "f"
                match_string
            when '.', ',', '(', ')', '{', '}', '[', ']', ';', '?', ':'
                match_punctuation
            when '+', '-', '*', '/', '%', '&', '|', '^', '!', '=', '<', '>', '~'
                match_operator
            else
                match_other
            end
        end
        self << Tuple.new(:EOF, "")
        @tokens
    end

    private def match_indentation
        match = @input[@position..].match(/^[\t ]+\b/)
        if match
            indentation = match[0]
            self << Tuple.new(:INDENT, match[0])
            @position += match[0].size
        end
    end

    private def match_newline
        while @position < @input.size && @input[@position] == '\n'
            self << Tuple.new(:NEWLINE, @input[@position])
            @position += 1
        end
    end

    private def match_comment
        start_pos = @position
        while @position < @input.size && @input[@position] != '\n'
            @position += 1
        end
        self << Tuple.new(:COMMENT, @input[start_pos...@position])
    end

    private def match_multiline_string
        delimiter = @input[@position..@position+2]
        start_pos = @position
        @position += 3
        while @position < @input.size && !@input[@position..@position+2].starts_with?(delimiter)
            if @input[@position] == '\\'
                @position += 1 # Skip escaped character
            end

            @position += 1
        end
        @position += 3 # Skip closing delimiter
        self << Tuple.new(:MULTILINE_STRING, @input[start_pos...@position])
    end

    private def match_number
        start_pos = @position
        if @input[@position..].starts_with?("0x")
            @position += 2 # Skip 0x
            while @position < @input.size && @input[@position].to_s =~ /[0-9a-fA-F]/
                @position += 1
            end
        else
            while @position < @input.size && @input[@position].to_s =~ /\d/
                @position += 1
            end

            if @position < @input.size && @input[@position] == '.'
                @position += 1
                while @position < @input.size && @input[@position].to_s =~ /\d/
                    @position += 1
                end
            end

            if @position < @input.size && @input[@position].to_s =~ /[eE]/
                @position += 1
                if @input[@position].to_s =~ /[+-]/
                    @position += 1 
                end
                while @position < @input.size && @input[@position].to_s =~ /\d/
                    @position += 1
                end
            end
        end
        if start_pos == @position
            self << Tuple.new(:NUMBER, @input[start_pos])
        else
            self << Tuple.new(:NUMBER, @input[start_pos...@position])
        end
    end

    private def match_string
        c = @input[@position]
        if c == '"' && @input[@position...@position+3] == "\"\"\""
            match_multiline_string
        elsif c == '\'' && @input[@position...@position+3] == "'''"
            match_multiline_string
        elsif c == 'f' && (@input[@position+1] == '"' || @input[@position+1] == '\'')
            @position += 1
            match_string
            self << Tuple.new(:FSTRING, @input[@position])
        else
            start_pos = @position
            @position += 1
            while @position < @input.size && @input[@position] != c
                if @input[@position] == '\\'
                    @position += 1 # Skip escaped character
                end

                @position += 1
            end

            @position += 1
            self << Tuple.new(:STRING, @input[start_pos...@position])
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
    
    private def match_other
        start_pos = @position
        if match = IDENTIFIER.match(@input[@position..])
            token_type = KEYWORDS.has_key?(match[0]) ? KEYWORDS[match[0]] : :IDENTIFIER
            self << Tuple.new(token_type, match[0])
            @position += match[0].size
        else
            token_type = :UNKNOWN
            if @input[@position] != ' ' # Skip whitespace
                self << Tuple.new(:UNKNOWN, @input[@position])
            end
            @position += 1
        end
    end
end