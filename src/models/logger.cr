require "colorize"

class NoirLogger
  enum LogLevel
    DEBUG
    VERBOSE
    INFO
    SUCCESS
    WARNING
    ERROR
    FATAL
    HEADING
  end

  def initialize(debug : Bool, verbose : Bool, colorize : Bool, no_log : Bool)
    @debug = debug
    @verbose = verbose
    @color_mode = colorize
    @no_log = no_log
  end

  def log(level : LogLevel, message : String)
    return if @no_log

    prefix = case level
             when LogLevel::DEBUG
               "❏".colorize(:dark_gray).toggle(@color_mode)
             when LogLevel::VERBOSE
               "▹".colorize(:dark_gray).toggle(@color_mode)
             when LogLevel::INFO
               "⚬".colorize(:light_cyan).toggle(@color_mode)
             when LogLevel::SUCCESS
               "✔".colorize(:green).toggle(@color_mode)
             when LogLevel::WARNING
               "▲".colorize(:yellow).toggle(@color_mode)
             when LogLevel::ERROR
               "✖︎".colorize(:red).toggle(@color_mode)
             when LogLevel::FATAL
               "☠".colorize(:red).toggle(@color_mode)
             when LogLevel::HEADING
               "★".colorize(:yellow).toggle(@color_mode)
             end

    STDERR.puts "#{prefix} #{message}"

    exit(1) if level == LogLevel::FATAL
  end

  def puts(message)
    STDOUT.puts message
  end

  def puts_sub(message)
    STDOUT.puts "  " + message
  end

  def heading(message)
    log(LogLevel::HEADING, message)
  end

  def info(message)
    log(LogLevel::INFO, message)
  end

  def success(message)
    log(LogLevel::SUCCESS, message)
  end

  def sub(message)
    return if @no_log
    STDERR.puts "  " + message
  end

  def warning(message)
    log(LogLevel::WARNING, message)
  end

  def error(message)
    log(LogLevel::ERROR, message)
  end

  def debug(message)
    return if @no_log || !@debug
    log(LogLevel::DEBUG, message.to_s)
  end

  def debug_sub(message)
    return if @no_log || !@debug
    STDERR.puts "  " + message.to_s
  end

  def verbose(message)
    return if @no_log || !@verbose
    log(LogLevel::VERBOSE, message)
  end

  def verbose_sub(message)
    return if @no_log || !@verbose
    STDERR.puts "  " + message
  end

  def fatal(message)
    log(LogLevel::FATAL, message)
  end
end
