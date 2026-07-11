require 'dry/cli'

module MyCLI
  class Build < Dry::CLI::Command
    desc "Build the project"

    option :force, type: :boolean, default: false
    argument :target, required: true

    def call(target:, **)
      puts "Building #{target}"
    end
  end
end

token = ENV["DRY_CLI_TOKEN"]
Dry::CLI.new(MyCLI).call
