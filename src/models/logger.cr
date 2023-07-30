require "colorize"

class NoirLogger
  def initialize(debug : Bool, colorize : Bool, no_log : Bool)
    @debug = debug
    @color_mode = colorize
    @no_log = no_log
  end

  def puts(message)
    puts message
  end

  def system(message)
    if @no_log
      return
    end

    prefix = "[*]".colorize(:light_cyan).toggle(@color_mode)
    STDERR.puts "#{prefix} #{message}"
  end

  def info(message)
    if @no_log
      return
    end

    prefix = "[I]".colorize(:light_blue).toggle(@color_mode)
    STDERR.puts "#{prefix} #{message}"
  end

  def info_sub(message)
    if @no_log
      return
    end

    STDERR.puts "    " + message
  end

  def debug(message)
    if @no_log
      return
    end

    if @debug
      prefix = "[D]".colorize(:dark_gray).toggle(@color_mode)
      STDERR.puts "#{prefix} #{message}"
    end
  end

  def debug_sub(message)
    if @no_log
      return
    end

    if @debug
      STDERR.puts "    " + message
    end
  end
end
