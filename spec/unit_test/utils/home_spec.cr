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
end
