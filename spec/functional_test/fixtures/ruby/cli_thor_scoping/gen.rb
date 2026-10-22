require "thor"

# A Thor::Group the file starts is a one-command program: `gen NAME [--force]`.
class Gen < Thor::Group
  argument :name, type: :string
  class_option :force, type: :boolean

  def create_it
    puts name
  end

  def finish_it
    puts "done"
  end
end

Gen.start(ARGV)
