require "../../spec_helper"
require "../../../src/models/logger.cr"

describe "NoirLogger" do
  describe "initialization" do
    it "creates logger with all options" do
      logger = NoirLogger.new(debug: true, verbose: true, colorize: true, no_log: false)
      logger.should_not be_nil
    end

    it "creates logger with minimal options" do
      logger = NoirLogger.new(debug: false, verbose: false, colorize: false, no_log: false)
      logger.should_not be_nil
    end
  end

  describe "log levels" do
    it "supports debug level" do
      logger = NoirLogger.new(debug: true, verbose: false, colorize: false, no_log: false)
      # Should not raise error
      logger.debug("debug message")
    end

    it "skips debug when debug is false" do
      logger = NoirLogger.new(debug: false, verbose: false, colorize: false, no_log: false)
      # Should not output anything but also not raise error
      logger.debug("debug message")
    end

    it "supports verbose level" do
      logger = NoirLogger.new(debug: false, verbose: true, colorize: false, no_log: false)
      logger.verbose("verbose message")
    end

    it "skips verbose when verbose is false" do
      logger = NoirLogger.new(debug: false, verbose: false, colorize: false, no_log: false)
      logger.verbose("verbose message")
    end

    it "supports info level" do
      logger = NoirLogger.new(debug: false, verbose: false, colorize: false, no_log: false)
      logger.info("info message")
    end

    it "supports success level" do
      logger = NoirLogger.new(debug: false, verbose: false, colorize: false, no_log: false)
      logger.success("success message")
    end

    it "supports warning level" do
      logger = NoirLogger.new(debug: false, verbose: false, colorize: false, no_log: false)
      logger.warning("warning message")
    end

    it "supports error level" do
      logger = NoirLogger.new(debug: false, verbose: false, colorize: false, no_log: false)
      logger.error("error message")
    end

    it "supports heading level" do
      logger = NoirLogger.new(debug: false, verbose: false, colorize: false, no_log: false)
      logger.heading("heading message")
    end
  end

  describe "no_log mode" do
    it "skips all logs when no_log is true" do
      logger = NoirLogger.new(debug: true, verbose: true, colorize: false, no_log: true)
      # Should not output anything but also not raise error
      logger.debug("debug message")
      logger.verbose("verbose message")
      logger.info("info message")
      logger.success("success message")
      logger.warning("warning message")
      logger.error("error message")
    end
  end

  describe "output methods" do
    it "supports puts" do
      logger = NoirLogger.new(debug: false, verbose: false, colorize: false, no_log: false)
      logger.puts("test message")
    end

    it "supports puts_sub" do
      logger = NoirLogger.new(debug: false, verbose: false, colorize: false, no_log: false)
      logger.puts_sub("sub message")
    end

    it "supports sub" do
      logger = NoirLogger.new(debug: false, verbose: false, colorize: false, no_log: false)
      logger.sub("sub message")
    end

    it "supports debug_sub" do
      logger = NoirLogger.new(debug: true, verbose: false, colorize: false, no_log: false)
      logger.debug_sub("debug sub message")
    end

    it "supports verbose_sub" do
      logger = NoirLogger.new(debug: false, verbose: true, colorize: false, no_log: false)
      logger.verbose_sub("verbose sub message")
    end
  end

  describe "colorize option" do
    it "works with colorize enabled" do
      logger = NoirLogger.new(debug: false, verbose: false, colorize: true, no_log: false)
      logger.info("colored message")
      logger.success("colored success")
      logger.warning("colored warning")
      logger.error("colored error")
    end

    it "works with colorize disabled" do
      logger = NoirLogger.new(debug: false, verbose: false, colorize: false, no_log: false)
      logger.info("plain message")
      logger.success("plain success")
      logger.warning("plain warning")
      logger.error("plain error")
    end
  end

  describe "LogLevel enum" do
    it "has all expected levels" do
      NoirLogger::LogLevel::DEBUG.should_not be_nil
      NoirLogger::LogLevel::VERBOSE.should_not be_nil
      NoirLogger::LogLevel::INFO.should_not be_nil
      NoirLogger::LogLevel::SUCCESS.should_not be_nil
      NoirLogger::LogLevel::WARNING.should_not be_nil
      NoirLogger::LogLevel::ERROR.should_not be_nil
      NoirLogger::LogLevel::FATAL.should_not be_nil
      NoirLogger::LogLevel::HEADING.should_not be_nil
    end
  end
end
