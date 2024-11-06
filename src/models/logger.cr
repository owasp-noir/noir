require "colorize"

class NoirLogger
  def initialize(debug : Bool, colorize : Bool, no_log : Bool)
    @debug = debug
    @color_mode = colorize
    @no_log = no_log
  end

  def puts(message)
    STDOUT.puts message
  end

  def puts_sub(message)
    STDOUT.puts "  " + message
  end

  def heading(message)
    if @no_log
      return
    end

    prefix = "★".colorize(:yellow).toggle(@color_mode)
    STDERR.puts "#{prefix} #{message}"
  end

  def info(message)
    if @no_log
      return
    end

    prefix = "⚑".colorize(:light_cyan).toggle(@color_mode)
    STDERR.puts "#{prefix} #{message}"
  end

  def success(message)
    if @no_log
      return
    end

    prefix = "✔".colorize(:green).toggle(@color_mode)
    STDERR.puts "#{prefix} #{message}"
  end

  def sub(message)
    if @no_log
      return
    end

    STDERR.puts "  " + message
  end

  def warning(message)
    prefix = "▲".colorize(:yellow).toggle(@color_mode)
    STDERR.puts "#{prefix} #{message}"
  end

  def error(message)
    prefix = "✖︎".colorize(:red).toggle(@color_mode)
    STDERR.puts "#{prefix} #{message}"
  end

  def debug(message)
    if @no_log
      return
    end

    if @debug
      prefix = "❏".colorize(:dark_gray).toggle(@color_mode)
      STDERR.puts "#{prefix} #{message}"
    end
  end

  def debug_sub(message)
    if @no_log
      return
    end

    if @debug
      STDERR.puts "  " + message.to_s
    end
  end

  def fatal(message)
    prefix = "☠".colorize(:red).toggle(@color_mode)
    STDERR.puts "#{prefix} #{message}"
    exit(1)
  end
end
