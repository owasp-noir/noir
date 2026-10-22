require "thor"

class Tool < Thor
  # A `private` section inside `class << self` ends with that block: it must
  # not hide the commands declared after it.
  class << self
    def exit_on_failure?
      true
    end

    private

    def helper
    end
  end

  desc "serve", "Start the server"
  def serve
    puts "serving"
  end

  # Nor does a `private` helper section of a nested class.
  class Reporter
    private

    def secret
    end
  end

  desc "build", "Build the project"
  def build
    puts "building"
  end

  # A bare `private` of the command class itself still applies to it.
  private

  def cleanup
    puts "cleanup"
  end
end

Tool.start(ARGV)
