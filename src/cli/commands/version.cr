require "../common"

# `noir version [--verbose]`
#
# Canonical entry point for version output. Legacy.rewrite turns
# `-v`, `--version`, and `--build-info` into the matching `version`
# invocation at the router layer.
module Noir::CLI::VersionCommand
  def self.run(argv : Array(String))
    verbose = false
    argv.each do |a|
      case a
      when "-h", "--help"
        print_help
        exit
      when "-V", "--verbose"
        verbose = true
      else
        Noir::CLI.die("Unknown option for `noir version`: #{a}")
      end
    end

    if verbose
      puts "Noir: #{Noir::VERSION}"
      puts "Crystal: #{Crystal::VERSION}"
      puts "LLVM: #{Crystal::LLVM_VERSION}"
      puts "Target: #{Crystal::TARGET_TRIPLE}"
    else
      puts Noir::VERSION
    end
  end

  def self.print_help
    cyan = ->(s : String) { Noir::CLI.name(s) }
    green = ->(s : String) { Noir::CLI.section(s) }

    puts <<-HELP
      #{green.call("USAGE:")}
        noir version [--verbose]

      #{green.call("OPTIONS:")}
        #{cyan.call("--verbose, -V")}          Also show Crystal/LLVM/target build details
                               (replaces v0 `--build-info`).

      #{green.call("LEGACY ALIASES:")}
        noir -v
        noir --version
        noir --build-info      → noir version --verbose
      HELP
  end
end
