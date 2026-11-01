module Noir
  # Whether a `Cargo.toml` declares a crate as a dependency, read from the
  # manifest's keys and not from any mention of the name. The one reader both
  # the Rust detectors and `RustEngine`'s crate gate use, so a detector never
  # fires on less than the gate accepts ("detect loose, gate strict").
  #
  #   axum = "0.7"                             axum.workspace = true
  #   "axum" = "0.7"                           web = { package = "axum" }
  #   [dependencies.axum]                      [target.'cfg(unix)'.dependencies.axum]
  module CargoDependency
    extend self

    @@patterns = Hash(String, Regex).new

    def pattern(name : String) : Regex
      @@patterns[name] ||= begin
        escaped = Regex.escape(name)
        Regex.new(
          "^[ \\t]*[\"']?#{escaped}[\"']?[ \\t]*[=.]" \
          "|^[ \\t]*\\[[^\\]\\n]*dependencies\\.[\"']?#{escaped}[\"']?[ \\t]*\\]" \
          "|^[^#\\n]*\\bpackage[ \\t]*=[ \\t]*[\"']#{escaped}[\"']",
          Regex::Options::MULTILINE)
      end
    end

    def declares?(manifest : String, name : String) : Bool
      manifest.matches?(pattern(name))
    end
  end
end
