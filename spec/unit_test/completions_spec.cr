require "../spec_helper"
require "../../src/completions"

describe "Completion Script Generation" do
  it "has a generate_zsh_completion_script method" do
    generate_zsh_completion_script.size.should be > 0
  end

  it "has a generate_bash_completion_script method" do
    generate_bash_completion_script.size.should be > 0
  end

  it "has a generate_fish_completion_script method" do
    generate_fish_completion_script.size.should be > 0
  end

  it "has a generate_elvish_completion_script method" do
    generate_elvish_completion_script.size.should be > 0
  end

  describe "Zsh completion" do
    it "includes all output formats" do
      script = generate_zsh_completion_script
      script.should contain("sarif")
      script.should contain("html")
      script.should contain("postman")
      script.should contain("powershell")
      script.should contain("mermaid")
      script.should contain("toml")
    end

    it "includes passive scan options" do
      script = generate_zsh_completion_script
      script.should contain("--passive-scan-severity")
      script.should contain("--passive-scan-auto-update")
      script.should contain("--passive-scan-no-update-check")
    end

    it "includes cache options" do
      script = generate_zsh_completion_script
      script.should contain("--cache-disable")
      script.should contain("--cache-clear")
    end

    it "includes technology options" do
      script = generate_zsh_completion_script
      script.should contain("--only-techs")
    end

    it "bundles long forms as aliases of short forms" do
      script = generate_zsh_completion_script
      # zsh spec form: '(-X --long)'{-X,--long}'[...]'
      script.should contain("(-b --base-path)")
      script.should contain("(-u --url)")
      script.should contain("(-f --format)")
      script.should contain("(-o --output)")
      script.should contain("(-P --passive-scan)")
      script.should contain("(-T --use-all-taggers)")
      script.should contain("(-t --techs)")
      script.should contain("(-d --debug)")
      script.should contain("(-v --version)")
      script.should contain("(-h --help)")
    end

    it "includes set-pvalue variants" do
      script = generate_zsh_completion_script
      %w[
        --set-pvalue
        --set-pvalue-header --set-pvalue-cookie --set-pvalue-query
        --set-pvalue-form --set-pvalue-json --set-pvalue-path
      ].each { |flag| script.should contain(flag) }
    end

    it "completes `noir help <cmd>` with subcommand list" do
      script = generate_zsh_completion_script
      # The help branch must describe commands at CURRENT == 3
      script.should contain("help)")
      script.should match(/help\)\s+if \(\( CURRENT == 3 \)\); then\s+_describe -t commands/)
    end
  end

  describe "Bash completion" do
    it "includes all output formats" do
      script = generate_bash_completion_script
      script.should contain("sarif")
      script.should contain("html")
      script.should contain("postman")
      script.should contain("powershell")
      script.should contain("mermaid")
      script.should contain("toml")
    end

    it "includes passive scan options" do
      script = generate_bash_completion_script
      script.should contain("--passive-scan-severity")
      script.should contain("--passive-scan-auto-update")
      script.should contain("--passive-scan-no-update-check")
    end

    it "includes cache options" do
      script = generate_bash_completion_script
      script.should contain("--cache-disable")
      script.should contain("--cache-clear")
    end

    it "includes passive-scan-severity completion values" do
      script = generate_bash_completion_script
      script.should contain("critical high medium low")
    end

    it "includes technology options" do
      script = generate_bash_completion_script
      script.should contain("--only-techs")
    end

    it "covers long-form flags in the prev case (file/value completion)" do
      script = generate_bash_completion_script
      # File-completion branch
      script.should contain("--base-path")
      script.should contain("--url")
      script.should contain("--output")
      script.should contain("--passive-scan-path")
      # Value-only branch (no file fallback)
      script.should contain("--exclude-codes")
      script.should contain("--exclude-path")
      script.should contain("--ai-agent-max-steps")
      script.should contain("--ai-max-token")
      script.should contain("--concurrency")
      script.should contain("--set-pvalue-header")
      script.should contain("--set-pvalue-path")
    end

    it "completes `noir help <cmd>` with subcommand list" do
      script = generate_bash_completion_script
      script.should contain("help)")
      script.should contain("compgen -W \"${commands}\"")
    end
  end

  describe "Fish completion" do
    # Fish completions register long flags with `-l name` (without the
    # leading --), so the substring assertions use that bare form.
    it "includes passive scan options" do
      script = generate_fish_completion_script
      script.should contain("-l passive-scan-severity")
      script.should contain("-l passive-scan-auto-update")
      script.should contain("-l passive-scan-no-update-check")
    end

    it "includes cache options" do
      script = generate_fish_completion_script
      script.should contain("-l cache-disable")
      script.should contain("-l cache-clear")
    end

    it "includes technology options" do
      script = generate_fish_completion_script
      script.should contain("-l only-techs")
    end

    it "registers set-pvalue variants" do
      script = generate_fish_completion_script
      %w[
        set-pvalue set-pvalue-header set-pvalue-cookie set-pvalue-query
        set-pvalue-form set-pvalue-json set-pvalue-path
      ].each { |flag| script.should contain("-l #{flag}") }
    end

    it "registers legacy include-* flags and status/exclude codes" do
      script = generate_fish_completion_script
      script.should contain("-l include-path")
      script.should contain("-l include-techs")
      script.should contain("-l include-callee")
      script.should contain("-l status-codes")
      script.should contain("-l exclude-codes")
    end

    it "registers AI agent flags" do
      script = generate_fish_completion_script
      script.should contain("-l ai-agent")
      script.should contain("-l ai-agent-max-steps")
      script.should contain("-l ai-native-tools-allowlist")
      script.should contain("-l ai-max-token")
    end
  end

  describe "v1 subcommand awareness" do
    it "zsh completion lists every top-level subcommand" do
      script = generate_zsh_completion_script
      %w[scan list cache config rules completion version help].each do |verb|
        script.should contain(verb)
      end
    end

    it "bash completion lists every top-level subcommand" do
      script = generate_bash_completion_script
      script.should contain("scan list cache config rules completion version help")
    end

    it "fish completion registers each top-level subcommand" do
      script = generate_fish_completion_script
      %w[scan list cache config rules completion version help].each do |verb|
        script.should contain("-a #{verb}")
      end
    end

    it "elvish completion registers the noir arg-completer with every verb" do
      script = generate_elvish_completion_script
      # Wires into the Elvish completion API
      script.should contain("edit:completion:arg-completer[noir]")
      # Lists each v1 verb as a candidate
      script.should contain("[scan list cache config rules completion version help]")
      # Falls back to file completion when the user starts typing a scan path
      script.should contain("edit:complete-filename")
    end
  end

  describe "Elvish completion shells/actions" do
    it "lists every supported shell, including elvish itself" do
      script = generate_elvish_completion_script
      %w[zsh bash fish elvish].each { |shell| script.should contain(shell) }
    end

    it "exposes config edit as a sub-action" do
      script = generate_elvish_completion_script
      script.should contain("[show edit init path]")
    end

    it "includes set-pvalue variants in scan-flags" do
      script = generate_elvish_completion_script
      %w[
        --set-pvalue
        --set-pvalue-header --set-pvalue-cookie --set-pvalue-query
        --set-pvalue-form --set-pvalue-json --set-pvalue-path
        --include-path --include-techs --include-callee
      ].each { |flag| script.should contain(flag) }
    end

    it "handles v0 bare-flag invocations (verb starting with -)" do
      script = generate_elvish_completion_script
      # The arg-completer must accept a leading flag as implicit scan
      script.should contain("str:has-prefix $verb -")
    end
  end
end
