require "../../../models/detector"

module Detector::Rust
  # Detects Rust command-line applications: crates depending on a CLI library
  # (clap, structopt, argh, bpaf, pico-args) or source that derives a parser /
  # uses `std::env::args()`. Gates the Rust CLI analyzer. Bare
  # `std::env::var(...)` (config reads, common in web crates) does not qualify.
  class Cli < Detector
    CLI_CRATES = ["clap", "structopt", "argh", "bpaf", "pico-args"]

    DERIVE_PARSER    = /#\[\s*derive\s*\([^)]*\b(?:Parser|Subcommand|Args)\b/
    DERIVE_STRUCTOPT = /#\[\s*derive\s*\([^)]*\bStructOpt\b/
    DERIVE_ARGH      = /#\[\s*derive\s*\([^)]*\bFromArgs\b/
    USE_CLI_LIB      = /\buse\s+(?:clap|structopt|argh|bpaf|pico_args)\b|\b(?:clap|structopt|argh|bpaf|pico_args)::/
    BUILDER_CMD      = /\bCommand::new\s*\(/
    ENV_ARGS         = /\b(?:std::)?env::args(?:_os)?\s*\(/

    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "Cargo.toml"
        return file_contents.includes?("dependencies") &&
          CLI_CRATES.any? { |crate| file_contents.matches?(/(?m)^\s*#{Regex.escape(crate)}\b/) }
      end

      return false unless filename.ends_with?(".rs")
      return true if file_contents.matches?(DERIVE_PARSER) || file_contents.matches?(DERIVE_STRUCTOPT) ||
                     file_contents.matches?(DERIVE_ARGH) || file_contents.matches?(USE_CLI_LIB)
      return true if file_contents.matches?(ENV_ARGS)
      # `Command::new(` alone is clap-builder only when clap is in use.
      return true if file_contents.includes?("clap") && file_contents.matches?(BUILDER_CMD)

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".rs") || File.basename(filename) == "Cargo.toml"
    end

    def set_name
      @name = "rust_cli"
    end
  end
end
