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

  it "coerces no_spinner config to Bool" do
    with_noir_home("no_spinner: yes\n") do |options|
      options["no_spinner"].should be_true
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

  describe "v0 -> v1 deliver/probe key migration" do
    # A v0.x `config.yaml` that hard-coded the old deliver keys must
    # keep working after the rename to PROBE/EXPORT internal keys.
    # Mapping is owned by LEGACY_CONFIG_KEY_MAP and applied inside
    # read_config before the merge with default_options.
    it "migrates send_req -> probe (scalar)" do
      with_noir_home("send_req: true\n") do |options|
        options["probe"].as_bool.should be_true
        options.has_key?("send_req").should be_false
      end
    end

    it "migrates send_proxy -> probe_via" do
      with_noir_home("send_proxy: http://127.0.0.1:8080\n") do |options|
        options["probe_via"].to_s.should eq("http://127.0.0.1:8080")
        options.has_key?("send_proxy").should be_false
      end
    end

    it "migrates send_es -> export_es" do
      with_noir_home("send_es: http://es:9200\n") do |options|
        options["export_es"].to_s.should eq("http://es:9200")
        options.has_key?("send_es").should be_false
      end
    end

    it "migrates send_with_headers -> probe_header (array)" do
      body = <<-YAML
        send_with_headers:
          - "Authorization: Bearer abc"
          - "X-Trace: 1"
        YAML
      with_noir_home(body) do |options|
        arr = options["probe_header"].as_a.map(&.to_s)
        arr.should eq(["Authorization: Bearer abc", "X-Trace: 1"])
        options.has_key?("send_with_headers").should be_false
      end
    end

    it "migrates use_matchers -> probe_match and use_filters -> probe_skip" do
      body = <<-YAML
        use_matchers:
          - "/api"
        use_filters:
          - "/admin"
        YAML
      with_noir_home(body) do |options|
        options["probe_match"].as_a.map(&.to_s).should eq(["/api"])
        options["probe_skip"].as_a.map(&.to_s).should eq(["/admin"])
        options.has_key?("use_matchers").should be_false
        options.has_key?("use_filters").should be_false
      end
    end

    it "does not overwrite a v1 key that's already set" do
      # If a config carries BOTH the v0 and v1 spelling (because the
      # user is mid-migration), the v1 entry wins — explicit user
      # intent shouldn't be clobbered by the legacy mapping.
      body = <<-YAML
        send_req: false
        probe: true
        YAML
      with_noir_home(body) do |options|
        options["probe"].as_bool.should be_true
        options.has_key?("send_req").should be_false
      end
    end
  end

  describe "override_path (CLI --config-file)" do
    # Pre-fix, `--config-file PATH` was only used by validation and
    # a post-CLI merge inside NoirRunner that re-overwrote every
    # CLI value. Now ConfigInitializer reads the override path
    # directly so the standard `defaults < file < CLI` precedence
    # falls out of `OptionParser.parse` writing on top of the
    # already-merged options.
    it "reads from override_path when supplied" do
      path = File.tempname("noir-cfg-override-")
      File.write(path, "concurrency: 17\n")
      begin
        options = ConfigInitializer.new(path).read_config
        options["concurrency"].to_s.should eq("17")
      ensure
        File.delete(path) if File.exists?(path)
      end
    end

    it "applies the v0 LEGACY_CONFIG_KEY_MAP to override files too" do
      path = File.tempname("noir-cfg-override-v0-")
      File.write(path, "send_req: yes\n")
      begin
        options = ConfigInitializer.new(path).read_config
        options["probe"].as_bool.should be_true
        options.has_key?("send_req").should be_false
      ensure
        File.delete(path) if File.exists?(path)
      end
    end

    it "does NOT auto-create the file when the override path is missing" do
      # Default config path auto-creates a template on first run, but
      # a missing user-supplied --config-file path is a typo — should
      # surface as a CliValidation error, not silently get backfilled
      # with a generated template at the user's chosen location.
      path = "/tmp/noir-cfg-override-missing-#{Random.rand(1_000_000)}.yaml"
      File.exists?(path).should be_false
      ConfigInitializer.new(path).setup
      File.exists?(path).should be_false
    end
  end
end
