require "../../../src/utils/home"

describe "get_home test" do
  it "returns NOIR_HOME environment variable if set" do
    ENV["NOIR_HOME"] = "/custom/noir/home"
    get_home.should eq("/custom/noir/home")
    ENV.delete("NOIR_HOME")
  end

  it "returns default config directory on Windows" do
    {% if flag?(:windows) %}
      ENV.delete("NOIR_HOME")
      get_home.should eq("#{ENV["APPDATA"]}\\noir")
    {% end %}
  end

  it "returns default config directory on non-Windows" do
    {% unless flag?(:windows) %}
      ENV.delete("NOIR_HOME")
      get_home.should eq("#{ENV["HOME"]}/.config/noir")
    {% end %}
  end

  # Env vars set outside a shell (Docker ENV, systemd Environment=) never
  # get the shell's tilde expansion, so a literal "~/noir" must be
  # expanded here or it resolves to a bogus "./~/noir" under the cwd.
  it "expands a leading ~ in NOIR_HOME" do
    saved = ENV["NOIR_HOME"]?
    ENV["NOIR_HOME"] = "~/some-noir-home"
    begin
      result = get_home
      result.starts_with?('~').should be_false
      {% unless flag?(:windows) %}
        result.should eq("#{ENV["HOME"]}/some-noir-home")
      {% end %}
    ensure
      if s = saved
        ENV["NOIR_HOME"] = s
      else
        ENV.delete("NOIR_HOME")
      end
    end
  end
end
