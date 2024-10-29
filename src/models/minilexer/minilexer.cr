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

  def trace
    line_number = -1
    lines = @input.split "\n"
    puts "Line Size: #{lines.size}, Token Count: #{tokens.size}"
    @tokens.each do |token|
      if line_number != token.line
        line_number = token.line
        puts "\nLine #{token.line}: " + lines[line_number - 1]
        next if token.type == :NEWLINE # Skip newline token
      end

      puts token.to_s
    end
  end

  def start_repl
    loop do
      print ">> "
      input = gets
      break if input.nil?
      input = input.chomp
      break if input == "exit"
      tokenize(input)
      trace
    end
  end
end
