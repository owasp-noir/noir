require "colorize"

lib LibC
  fun usleep(useconds : UInt32) : Int32
end

class NoirLogger
  SPINNER_FRAMES      = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  SHIMMER_COLORS      = [159, 255, 250, 247, 245]
  SHIMMER_BAND_RADIUS = SHIMMER_COLORS.size - 1

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

  @stdout_busy : Atomic(Int8)

  def initialize(debug : Bool, verbose : Bool, colorize : Bool, no_log : Bool, no_spinner : Bool = false)
    @debug = debug
    @verbose = verbose
    @color_mode = colorize
    @no_log = no_log
    @no_spinner = no_spinner
    @output_mutex = Mutex.new
    @spinner_active = false
    @stdout_busy = Atomic(Int8).new(0_i8)
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

    write_stderr_line "#{prefix} #{message}"

    exit(1) if level == LogLevel::FATAL
  end

  def loading(message : String, &)
    if @no_log
      return yield
    end

    unless spinner_enabled?
      info(message)
      return yield
    end

    stop = Atomic(Int8).new(0_i8)

    # Set @spinner_active thread-safely
    while @stdout_busy.compare_and_set(0_i8, 1_i8, :acquire_release, :acquire)[1] == false
      Fiber.yield
    end
    @spinner_active = true
    @stdout_busy.set(0_i8)

    thread = Thread.new do
      index = 0
      while stop.get == 0_i8
        # Non-blocking lock try
        _, success = @stdout_busy.compare_and_set(0_i8, 2_i8, :acquire_release, :acquire)
        if success
          render_spinner(message, index)
          index += 1
          @stdout_busy.set(0_i8)
        end
        LibC.usleep(60000_u32)
      end

      # Spin-acquire for final cleanup
      while @stdout_busy.compare_and_set(0_i8, 2_i8, :acquire_release, :acquire)[1] == false
        LibC.usleep(100_u32)
      end
      clear_spinner_line
      @spinner_active = false
      @stdout_busy.set(0_i8)
    end

    begin
      yield
    ensure
      stop.set(1_i8)
      thread.join
    end
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
    write_stderr_line "  " + message
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
    write_stderr_line "  " + message.to_s
  end

  def verbose(message)
    return if @no_log || !@verbose
    log(LogLevel::VERBOSE, message)
  end

  def verbose_sub(message)
    return if @no_log || !@verbose
    write_stderr_line "  " + message
  end

  def fatal(message)
    log(LogLevel::FATAL, message)
  end

  private def spinner_enabled? : Bool
    @color_mode && !@no_spinner && STDERR.tty?
  end

  private def render_spinner(message : String, index : Int32)
    frame = SPINNER_FRAMES[index % SPINNER_FRAMES.size]
    line = shimmer("#{frame} #{message}", index)

    STDERR.print "\r\e[2K#{line}"
    STDERR.flush
  end

  private def write_stderr_line(message : String)
    # Spin-acquire for the main fiber (cooperative yielding)
    while @stdout_busy.compare_and_set(0_i8, 1_i8, :acquire_release, :acquire)[1] == false
      Fiber.yield
    end

    clear_spinner_line if @spinner_active
    STDERR.puts message
    STDERR.flush

    @stdout_busy.set(0_i8)
    nil
  end

  private def clear_spinner_line
    STDERR.print "\r\e[2K"
    STDERR.flush
  end

  private def shimmer(text : String, index : Int32) : String
    chars = text.chars
    return text if chars.empty?

    travel = chars.size + SHIMMER_BAND_RADIUS * 2
    highlight = index % travel - SHIMMER_BAND_RADIUS

    String.build do |io|
      chars.each_with_index do |char, char_index|
        distance = (char_index - highlight).abs
        color = if distance <= SHIMMER_BAND_RADIUS
                  SHIMMER_COLORS[distance]
                else
                  SHIMMER_COLORS.last
                end
        io << "\e[38;5;" << color << "m" << char
      end
      io << "\e[0m"
    end
  end
end
