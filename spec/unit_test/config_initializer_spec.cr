require "../spec_helper"
require "../../src/config_initializer"
require "file_utils"

# Drives ConfigInitializer.read_config against on-disk config.yaml
# files under a temp NOIR_HOME. Restores NOIR_HOME after every spec so
# the host environment isn't polluted.
private def with_noir_home(yaml_body : String, &)
  dir = File.tempname("noir-config-spec-")
  Dir.mkdir(dir)
  File.write(File.join(dir, "config.yaml"), yaml_body)

  saved = ENV["NOIR_HOME"]?
  ENV["NOIR_HOME"] = dir
  begin
    yield ConfigInitializer.new.read_config
  ensure
    if s = saved
      ENV["NOIR_HOME"] = s
    else
      ENV.delete("NOIR_HOME")
    end
    FileUtils.rm_rf(dir)
  end
end

describe ConfigInitializer do
  # Regression: read_config used to call `symbolized_hash[key] == "yes"`
  # without checking presence. A partial config (only one of the
  # boolean keys set) would raise KeyError on the next iteration, get
  # swallowed by the outer rescue, and silently revert every setting
  # to defaults. The `[key]?` rewrite keeps each setting honored.
  it "honors partial configs that only set one boolean key" do
    with_noir_home("color: yes\n") do |options|
      options["color"].should be_true
      # Other keys still come from defaults.
      options["debug"].should be_false
    end
  end

  it "coerces legacy yes/no strings to Bool for cache_disable / status_codes" do
    body = <<-YAML
      cache_disable: yes
      status_codes: yes
      YAML
    with_noir_home(body) do |options|
      options["cache_disable"].should be_true
      options["status_codes"].should be_true
    end
  end

  it "normalizes a bare-string passive_scan_path into a single-element array" do
    with_noir_home("passive_scan_path: ./team-rules\n") do |options|
      arr = options["passive_scan_path"].as_a
      arr.size.should eq(1)
      arr.first.to_s.should eq("./team-rules")
    end
  end

  it "treats an empty-string array key as an empty array" do
    with_noir_home("base: \"\"\n") do |options|
      options["base"].as_a.empty?.should be_true
    end
  end

  it "falls back to defaults when the YAML is malformed" do
    with_noir_home("this is :: not valid :: yaml :\n") do |options|
      # Defaults are returned wholesale; no key from the broken file
      # is propagated, but the structure stays valid.
      options.has_key?("color").should be_true
    end
  end
end
