require "../../../models/detector"

module Detector::Rust
  # Detects Rust command-line applications: crates depending on a CLI library
  # (clap, structopt, argh, bpaf, pico-args, getopts) or source that derives a
  # parser / uses `std::env::args()`. Gates the Rust CLI analyzer. Bare
  # `std::env::var(...)` (config reads, common in web crates) does not qualify.
  class Cli < Detector
    CLI_CRATES = ["clap", "structopt", "argh", "bpaf", "pico-args", "getopts"]
    # Single-pass alternation over CLI_CRATES — the previous per-crate
    # interpolated literal recompiled (and rescanned) once per crate for
    # every Cargo.toml.
    CARGO_CLI_DEP = /(?m)^\s*(?:clap|structopt|argh|bpaf|pico\-args|getopts)\b/

    DERIVE_PARSER    = /#\[\s*derive\s*\([^)]*\b(?:Parser|Subcommand|Args)\b/
    DERIVE_STRUCTOPT = /#\[\s*derive\s*\([^)]*\bStructOpt\b/
    DERIVE_ARGH      = /#\[\s*derive\s*\([^)]*\bFromArgs\b/
    USE_CLI_LIB      = /\buse\s+(?:clap|structopt|argh|bpaf|pico_args|getopts)\b|\b(?:clap|structopt|argh|bpaf|pico_args|getopts)::/
    BUILDER_CMD      = /\bCommand::new\s*\(/
    ENV_ARGS         = /\b(?:std::)?env::args(?:_os)?\s*\(/

    # Single-pass union of the standalone source markers (the clap-builder
    # check below stays separate: it is gated on `includes?("clap")`). The
    # previous chain scanned the whole file up to 5 times on non-CLI Rust
    # sources — the common case.
    SOURCE_MARKER = Regex.union(
      DERIVE_PARSER, DERIVE_STRUCTOPT, DERIVE_ARGH, USE_CLI_LIB, ENV_ARGS,
    )

    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "Cargo.toml"
        return file_contents.includes?("dependencies") &&
          file_contents.matches?(CARGO_CLI_DEP)
      end

      return false unless filename.ends_with?(".rs")
      return true if file_contents.matches?(SOURCE_MARKER)
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
