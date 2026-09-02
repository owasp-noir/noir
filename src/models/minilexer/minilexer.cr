class MiniLexer
  property tokens : Array(Token)
  property mode : Symbol # :normal, :persistent

  def initialize
    @mode = :normal
    @tokens = [] of Token
    @position = 0
    @input = ""
    @pos_line_array = Array(Tuple(Int32, Int32)).new
  end

  def mode=(mode)
    @mode = mode
  end

  def line : Int
    pos_index = 0
    line_index = 1
    i = @pos_line_array.size - 1
    while 0 < i
      pos = @pos_line_array[i][pos_index]
      line = @pos_line_array[i][line_index]
      if pos < @position
        return line + @input[pos + 1..@position].count("\n")
      end
      i -= 1
    end

    line = @input[0..@position].count("\n") + 1
    @pos_line_array << Tuple.new(@position, line)

    line
  end

  def <<(t : Tuple(Symbol, String))
    @tokens << Token.new(t[0], t[1], @tokens.size, @position, line())
  end

  def <<(t : Tuple(Symbol, Char))
    @tokens << Token.new(t[0], t[1].to_s, @tokens.size, @position, line())
  end

  def <<(t : Tuple(Symbol, Char | String))
    @tokens << Token.new(t[0], t[1].to_s, @tokens.size, @position, line())
  end

  def tokenize(@input : String) : Array(Token)
    results = tokenize_logic(input)

    if @mode == :persistent
      @tokens = @tokens + results
    else
      @position = 0
      @pos_line_array.clear
    end

    results
  end

  def tokenize_logic(@input : String) : Array(Token)
    results = [] of Token
    results
  end

  def find(token_type : Symbol) : Array(Token)
    @tokens.select { |token| token.type == token_type }
  end

  # Token dump for debugging a lexer by hand. Written to STDERR, like every
  # other Noir diagnostic: STDOUT carries the report, so a `puts` here would
  # land in the middle of a `-f json` / `-f sarif` document the moment anyone
  # called this from inside a scan. Nothing calls it today, which is exactly
  # why the stream it writes to has to be right before someone does.
  def trace(io : IO = STDERR)
    line_number = -1
    lines = @input.split "\n"
    io.puts "Line Size: #{lines.size}, Token Count: #{tokens.size}"
    @tokens.each do |token|
      if line_number != token.line
        line_number = token.line
        io.puts "\nLine #{token.line}: " + lines[line_number - 1]
        next if token.type == :NEWLINE # Skip newline token
      end

      io.puts token.to_s
    end
  end
end
