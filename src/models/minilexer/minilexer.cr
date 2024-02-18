class MiniLexer
  property tokens : Array(Token)
  property mode : Symbol # :normal, :persistent

  def initialize
    @mode = :normal
    @tokens = [] of Token
    @position = 0
    @input = ""
    @line = 1
  end

  def mode=(mode)
    @mode = mode
  end

  def <<(t :  Tuple(Symbol, String))
    @tokens << Token.new(t[0], t[1], @tokens.size, @position, @line)
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

  def trace()    
    line_number = 1
    source_line = ""
    lines = @input.split "\n"
    puts "line size: #{lines.size}, token number: #{tokens.size}"
    @tokens.each do |token|      
      if token.line == line_number
        puts "\nLine #{line_number}: " + lines[line_number-1]
        line_number += 1
      end
      puts token.to_s
    end
  end
end
