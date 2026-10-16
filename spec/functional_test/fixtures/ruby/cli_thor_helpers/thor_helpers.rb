require "thor"

class Tool < Thor
  # Singleton methods are Thor configuration hooks, never commands.
  class << self
    def exit_on_failure?
      true
    end

    def banner(command, *)
      "tool #{command.usage}"
    end
  end

  desc "serve", "Start the server"
  option :port, type: :numeric
  def serve
    puts "serving"
  end

  protected

  def helper_protected
    puts "helper"
  end

  public

  # A one-line singleton block closes itself and must not swallow `build`.
  class << self; def one_line_helper; end; end

  desc "build", "Build the project"
  def build
    puts "building"
  end
end

# Thor::Group has no commands: every public method is a generator step and
# `desc` takes the description alone.
class Generator < Thor::Group
  desc "Generates files\n\n\ttool generate writes the files"

  def create_it
    puts "create"
  end

  def finish_it
    puts "finish"
  end
end

# Thor::Actions subclasses are plain helper classes.
class MigrationFile < Thor::Actions::CreateFile
  def identical?
    true
  end
end

Tool.start(ARGV)
