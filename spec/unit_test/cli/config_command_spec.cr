require "../../spec_helper"
require "../../../src/cli/commands/config"

# Each spec snapshots the relevant env vars and restores them on the
# way out so concurrent / later specs see a clean slate.
private def with_editor_env(visual : String? = nil, editor : String? = nil, &)
  saved_visual = ENV["VISUAL"]?
  saved_editor = ENV["EDITOR"]?
  if v = visual
    ENV["VISUAL"] = v
  else
    ENV.delete("VISUAL")
  end
  if e = editor
    ENV["EDITOR"] = e
  else
    ENV.delete("EDITOR")
  end

  yield
ensure
  if v = saved_visual
    ENV["VISUAL"] = v
  else
    ENV.delete("VISUAL")
  end
  if e = saved_editor
    ENV["EDITOR"] = e
  else
    ENV.delete("EDITOR")
  end
end

describe "Noir::CLI::ConfigCommand.pick_editor" do
  it "prefers $VISUAL when both are set" do
    with_editor_env(visual: "code --wait", editor: "vim") do
      Noir::CLI::ConfigCommand.pick_editor.should eq("code --wait")
    end
  end

  it "falls back to $EDITOR when $VISUAL is unset" do
    with_editor_env(visual: nil, editor: "nano") do
      Noir::CLI::ConfigCommand.pick_editor.should eq("nano")
    end
  end

  it "treats an empty $VISUAL as unset and falls back to $EDITOR" do
    with_editor_env(visual: "", editor: "nano") do
      Noir::CLI::ConfigCommand.pick_editor.should eq("nano")
    end
  end

  it "treats an empty $EDITOR as unset and falls back to the platform default" do
    with_editor_env(visual: "", editor: "") do
      Noir::CLI::ConfigCommand.pick_editor.should eq(Noir::CLI::ConfigCommand.default_editor)
    end
  end

  it "uses the platform default when neither env var is set" do
    with_editor_env(visual: nil, editor: nil) do
      Noir::CLI::ConfigCommand.pick_editor.should eq(Noir::CLI::ConfigCommand.default_editor)
    end
  end
end

describe "Noir::CLI::ConfigCommand.default_editor" do
  it "returns a non-empty editor command for the host platform" do
    Noir::CLI::ConfigCommand.default_editor.should_not be_empty
  end

  it "matches the platform — vi on Unix, notepad on Windows" do
    {% if flag?(:windows) %}
      Noir::CLI::ConfigCommand.default_editor.should eq("notepad")
    {% else %}
      Noir::CLI::ConfigCommand.default_editor.should eq("vi")
    {% end %}
  end
end

describe "Noir::CLI::ConfigCommand.config_path" do
  it "resolves under NOIR_HOME when set" do
    saved = ENV["NOIR_HOME"]?
    ENV["NOIR_HOME"] = "/tmp/noir-test-home"
    begin
      Noir::CLI::ConfigCommand.config_path.should eq("/tmp/noir-test-home/config.yaml")
    ensure
      if s = saved
        ENV["NOIR_HOME"] = s
      else
        ENV.delete("NOIR_HOME")
      end
    end
  end
end

describe "Noir::CLI::ConfigCommand::ACTIONS" do
  it "lists every public action exactly once" do
    Noir::CLI::ConfigCommand::ACTIONS.should eq(%w[show edit init path])
  end
end
