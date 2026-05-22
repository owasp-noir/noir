require "../common"

# `noir version [--verbose]`
#
# Replaces v0's `-v`/`--version` (still works as silent alias inside the
# scan parser) and `--build-info` (rewritten by Legacy to `version
# --verbose`).
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
    puts <<-HELP
      USAGE:
        noir version [--verbose]

      OPTIONS:
        --verbose, -V        Also show Crystal/LLVM/target build details
                             (replaces v0 `--build-info`).

      LEGACY ALIASES:
        noir -v
        noir --version
        noir --build-info    → noir version --verbose
      HELP
  end
end
