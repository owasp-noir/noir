require "colorize"

class NoirLogger
  def initialize(debug : Bool, colorize : Bool)
    @debug = debug
    @color_mode = colorize
  end

  def puts(message)
    puts message
  end

  def system(message)
    if @color_mode
      prefix = "[*] ".colorize(:light_cyan)
      STDERR.puts "#{prefix}#{message}"
    else
      STDERR.puts "[*]" + message
    end
  end

  def info(message)
    if @color_mode
      prefix = "[I] ".colorize(:light_blue)
      STDERR.puts "#{prefix}#{message}"
    else
      STDERR.puts "[I] " + message
    end
  end

  def info_sub(message)
    STDERR.puts "    " + message
  end

  def debug(message)
    if @debug
      if @color_mode
        prefix = "[D] ".colorize(:dark_gray)
        STDERR.puts "#{prefix}#{message}"
      else
        STDERR.puts "[D] " + message
      end
    end
  end

  def debug_sub(message)
    if @debug
      STDERR.puts "    " + message
    end
  end
end
