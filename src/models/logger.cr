require "colorize"

lib LibC
  fun usleep(useconds : UInt32) : Int32
end

class NoirLogger
  SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  # Frame delay. `sleep` (fiber-aware) rather than `LibC.usleep`, which
  # would block the whole scheduler now that the spinner is a fiber.
  SPINNER_INTERVAL    = 60.milliseconds
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

  # `IO::Error#os_error` is `Errno | WinError | WasiError | Nil` — on
  # Windows a broken pipe surfaces as a `WinError`, not an `Errno`, so
  # comparing straight against `Errno::EPIPE` silently never matches
  # there. `WinError#to_errno` normalizes it (`ERROR_BROKEN_PIPE` /
  # `ERROR_NO_DATA` both map to `Errno::EPIPE`). Noir doesn't ship a WASI
  # build, so `WasiError` — whose own `#to_errno` doesn't even compile on
  # every native target (it references an `Errno` member some platforms'
  # bindings omit) — is intentionally left out of this check.
  def self.broken_pipe?(ex : IO::Error) : Bool
    case os_error = ex.os_error
    when Errno
      os_error == Errno::EPIPE
    when WinError
      os_error.to_errno == Errno::EPIPE
    else
      false
    end
  end

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

    # Must be a fiber, not a `Thread`. Crystal 1.21 requires every thread
    # that touches the scheduler to belong to an execution context, and a
    # bare `Thread.new` has none — the `STDERR.print`/`flush` inside
    # `render_spinner` then aborts the process with
    # "Thread#execution_context cannot be nil (NilAssertionError)".
    # Only reproducible on a TTY, because that is the sole condition under
    # which `spinner_enabled?` is true.
    finished = Channel(Nil).new

    spawn do
      # The outer `ensure` guarantees `finished.send(nil)` fires no matter
      # how this fiber body exits. It matters because an unhandled
      # exception inside a spawned fiber doesn't crash the process —
      # Crystal just prints "Unhandled exception in spawn" and lets the
      # fiber die — so without this, any exception here (render_spinner
      # and clear_spinner_line no longer raise on IO::Error, but a future
      # change or an unrelated bug could still raise something) would kill
      # the fiber before it ever calls `finished.send`, and the caller's
      # `ensure { stop.set(1_i8); finished.receive }` below would then
      # block forever on a channel nothing is left alive to send on.
      # Confirmed empirically: an unhandled raise here previously hung a
      # minimal repro of this exact fiber/channel shape indefinitely.
      begin
        index = 0
        while stop.get == 0_i8
          # Non-blocking lock try
          _, success = @stdout_busy.compare_and_set(0_i8, 2_i8, :acquire_release, :acquire)
          if success
            begin
              render_spinner(message, index)
              index += 1
            ensure
              @stdout_busy.set(0_i8)
            end
          end
          sleep SPINNER_INTERVAL
        end

        # Spin-acquire for final cleanup
        while @stdout_busy.compare_and_set(0_i8, 2_i8, :acquire_release, :acquire)[1] == false
          Fiber.yield
        end
        begin
          clear_spinner_line
          @spinner_active = false
        ensure
          @stdout_busy.set(0_i8)
        end
      ensure
        finished.send(nil)
      end
    end

    begin
      yield
    ensure
      stop.set(1_i8)
      # Wait for the frame loop to clear its line before returning, so the
      # next writer doesn't land on top of a half-drawn spinner.
      finished.receive
    end
  end

  def puts(message)
    STDOUT.puts message
  rescue ex : IO::Error
    # Downstream reader closed its end of the pipe (`noir ... | head`, `|
    # jq -e`, etc.) — nothing left to write for, exit quietly instead of a
    # broken-pipe stack trace. `puts`/`puts_sub` also carry real report
    # content (e.g. OutputBuilderPassiveScan's plain-text findings), so
    # anything other than a broken pipe (disk full, a bad fd, ...) is a
    # real failure and must still surface, not be swallowed into a lying
    # exit(0).
    raise ex unless NoirLogger.broken_pipe?(ex)
    exit(0)
  end

  def puts_sub(message)
    STDOUT.puts "  " + message
  rescue ex : IO::Error
    raise ex unless NoirLogger.broken_pipe?(ex)
    exit(0)
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
  rescue IO::Error
    # STDERR here is pure progress UI, never primary report content — on
    # any write failure (broken pipe, closed terminal, ...) there's
    # nothing useful to do but stop trying. Swallowing rather than
    # exiting/re-raising also guarantees this can never kill the spinner
    # fiber before it reaches its `finished.send(nil)` cleanup in `loading`.
  end

  private def write_stderr_line(message : String)
    # Spin-acquire for the main fiber (cooperative yielding)
    while @stdout_busy.compare_and_set(0_i8, 1_i8, :acquire_release, :acquire)[1] == false
      Fiber.yield
    end

    clear_spinner_line if @spinner_active
    STDERR.puts message
    STDERR.flush
    nil
  rescue IO::Error
    # STDERR here is pure progress/debug logging, never primary report
    # content (see NoirLogger#puts for the stream that does carry content
    # and needs the stricter broken-pipe-vs-real-failure distinction) — on
    # any write failure there's nothing useful to do but give up on this
    # line. Swallowing unconditionally (rather than exiting or re-raising)
    # means this can never strand @stdout_busy at "held" (an unhandled
    # exception inside a spawned fiber doesn't stop the whole process —
    # Crystal just prints "Unhandled exception in spawn" and the fiber
    # dies — so every other logging fiber would otherwise spin on the
    # acquire loop above at 100% CPU for good) or skip `log`'s
    # `exit(1) if level == LogLevel::FATAL`.
    nil
  ensure
    @stdout_busy.set(0_i8)
  end

  private def clear_spinner_line
    STDERR.print "\r\e[2K"
    STDERR.flush
  rescue IO::Error
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
