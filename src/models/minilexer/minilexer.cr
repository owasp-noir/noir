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

  def tokenize(@input : String) : Array(Token)
    results = tokenize_logic(input)

    if @mode == :persistent
      @tokens = @tokens + results
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
    line_number = 1
    # source_line = ""
    lines = @input.split "\n"
    puts "line size: #{lines.size}, token number: #{tokens.size}"
    @tokens.each do |token|
      if token.line == line_number
        puts "\nLine #{line_number}: " + lines[line_number - 1]
        line_number += 1
      end
      puts token.to_s
    end
  end
end
