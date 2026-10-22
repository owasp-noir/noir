require "thor"

# Generator base class that something else starts: no entry point here, so it
# is not a program of its own and its steps are not commands.
class BaseGenerator < Thor::Group
  argument :name, type: :string
  class_option :skip_tests, type: :boolean

  def create_files
    puts name
  end
end
