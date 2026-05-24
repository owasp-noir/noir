require "../common"

# `noir version [--verbose]`
#
# Canonical entry point for version output. Legacy.rewrite turns
# `-v`, `--version`, and `--build-info` into the matching `version`
# invocation at the router layer.
module Noir::CLI::VersionCommand
  # Parsed argv. `unknown` is set when an unrecognised token appears so
  # the spec layer can verify the validation rule without going through
  # the `die` exit path that `run` enforces.
  record Parsed, verbose : Bool, help : Bool, unknown : String?

  def self.parse_argv(argv : Array(String)) : Parsed
    verbose = false
    help = false
    unknown : String? = nil
    argv.each do |a|
      case a
      when "-h", "--help"
        help = true
      when "-V", "--verbose"
        verbose = true
      else
        unknown ||= a
      end
    end
    Parsed.new(verbose: verbose, help: help, unknown: unknown)
  end

  def self.run(argv : Array(String))
    parsed = parse_argv(argv)

    if parsed.help
      print_help
      exit
    end

    if u = parsed.unknown
      Noir::CLI.die("Unknown option for `noir version`: #{u}")
    end

    print_version(parsed.verbose)
  end

  def self.print_version(verbose : Bool, io : IO = STDOUT)
    if verbose
      io.puts "Noir: #{Noir::VERSION}"
      io.puts "Crystal: #{Crystal::VERSION}"
      io.puts "LLVM: #{Crystal::LLVM_VERSION}"
      io.puts "Target: #{Crystal::TARGET_TRIPLE}"
    else
      io.puts Noir::VERSION
    end
  end

  def self.print_help(io : IO = STDOUT)
    cyan = ->(s : String) { Noir::CLI.name(s) }
    green = ->(s : String) { Noir::CLI.section(s) }

    io.puts <<-HELP
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
