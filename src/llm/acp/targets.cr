module LLM
  # ACP agent targets Noir knows how to launch.
  #
  # Anything outside this set would be executed as an arbitrary local process
  # (`--ai-provider "acp:rm -rf /"` → command `rm`, args `["-rf", "/"]`), which
  # is a code-execution hole when the provider string comes from an untrusted
  # config file. Custom targets are refused unless the operator explicitly opts
  # in via `NOIR_ACP_ALLOW_CUSTOM_COMMAND=1`.
  #
  # This lives in its own dependency-free file because two layers need it and
  # they must not disagree:
  #
  #   * `LLM::ACPClient` — the exec sink, which raises mid-scan.
  #   * `Noir::CliValidation` — the pre-flight check, so a bad `--ai-provider`
  #     is a clean error before a scan starts rather than a raise partway
  #     through it.
  #
  # The two used to carry byte-identical `%w[...]` literals, with a comment on
  # one saying it was "kept in sync with" the other. For a list whose whole
  # purpose is bounding what Noir will exec, "kept in sync by hand" is the
  # wrong mechanism: the pre-flight check silently narrowing or widening
  # relative to the sink is exactly the drift that matters.
  #
  # Requiring `acp/client.cr` from `cli_validation.cr` would have worked too,
  # but it pulls the `acp` shard and `log` into the CLI validation path for one
  # array. Hence this file, which requires nothing.
  module ACPTargets
    KNOWN = %w[codex gemini claude claude-code]

    # `codex` / `gemini` / `claude` / `claude-code`
    def self.known?(target : String) : Bool
      KNOWN.includes?(target)
    end

    def self.join : String
      KNOWN.join(", ")
    end
  end
end
