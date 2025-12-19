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

  describe "Zsh completion" do
    it "includes all output formats" do
      script = generate_zsh_completion_script
      script.should contain("sarif")
      script.should contain("html")
      script.should contain("postman")
      script.should contain("powershell")
      script.should contain("mermaid")
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
  end

  describe "Bash completion" do
    it "includes all output formats" do
      script = generate_bash_completion_script
      script.should contain("sarif")
      script.should contain("html")
      script.should contain("postman")
      script.should contain("powershell")
      script.should contain("mermaid")
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
  end

  describe "Fish completion" do
    it "includes passive scan options" do
      script = generate_fish_completion_script
      script.should contain("--passive-scan-severity")
      script.should contain("--passive-scan-auto-update")
      script.should contain("--passive-scan-no-update-check")
    end

    it "includes cache options" do
      script = generate_fish_completion_script
      script.should contain("--cache-disable")
      script.should contain("--cache-clear")
    end
  end
end
