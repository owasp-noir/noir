require "thor"

API_TOKEN = ENV["API_TOKEN"]

class CLI < Thor
  desc "serve", "Start the server"
  method_option :port, type: :numeric
  option :verbose, type: :boolean
  def serve
    puts "serving"
  end

  desc "build TARGET", "Build the project"
  def build(target)
    puts target
  end

  def self.exit_on_failure?
    true
  end

  no_commands do
    def render_banner
      puts "banner"
    end
  end

  private

  def internal_cleanup
    puts "cleanup"
  end
end

CLI.start(ARGV)
