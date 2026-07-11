require 'clamp'

class ClampApp < Clamp::Command
  option "--verbose", :flag, "Enable verbose output"
  parameter "FILE", "input file"

  subcommand "serve", "Start the server" do
    option ["-p", "--port"], "PORT", "port to bind"

    def execute
      puts "serving"
    end
  end

  def execute
    # Ordinary local-variable assignment reusing the word "option" — must
    # NOT be mistaken for the `option "--flag", ...` DSL call (regression
    # for the CLAMP_OPTION_LONG false-positive).
    option = default? ? "--json" : "--text"
    puts option
  end
end

token = ENV["CLAMP_TOKEN"]
ClampApp.run
