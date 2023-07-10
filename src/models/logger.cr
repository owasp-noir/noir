class NoirLogger
  def initialize(debug : Bool, colorize : Bool)
    @debug = debug
    @color_mode = colorize
  end

  def puts(message)
    puts message
  end

  def info(message)
    STDERR.puts message
  end

  def info(message, depth)
    case depth
    when 0
      STDERR.puts message
    when 1
      STDERR.puts "  #{message}"
    when 2
      STDERR.puts "    #{message}"
    when 3
      STDERR.puts "      #{message}"
    else
      STDERR.puts "        #{message}"
    end
    STDERR.puts message
  end

  def debug(message)
    STDERR.puts message if @debug
  end
end
