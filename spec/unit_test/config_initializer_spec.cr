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

  it "uses defaults for an empty config file" do
    # An empty config.yaml is a legitimate "no overrides" state, not a
    # parse error — read_config returns defaults without churning
    # through the (would-raise) YAML path.
    with_noir_home("") do |options|
      options.has_key?("color").should be_true
      options["color"].should be_true
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

  # Every consumer of these keys reads them through `YAML::Any#as_i`. A
  # quoted number parses as a String and used to raise "Cast from String to
  # Int64 failed" inside the AI analyzer — caught as an analyzer failure, so
  # the run exited 0 with AI analysis silently skipped. The generated
  # template models the quoted spelling itself (`concurrency: "…"`), so it is
  # the shape users copy.
  describe "INTEGER_CONFIG_KEYS coercion" do
    it "coerces a quoted ai_max_token into an Int" do
      with_noir_home("ai_max_token: \"4000\"\n") do |options|
        options["ai_max_token"].as_i.should eq(4000)
      end
    end

    it "coerces a quoted ai_agent_max_steps into an Int" do
      with_noir_home("ai_agent_max_steps: \"7\"\n") do |options|
        options["ai_agent_max_steps"].as_i.should eq(7)
      end
    end

    it "leaves a real YAML int alone" do
      with_noir_home("ai_max_token: 1200\n") do |options|
        options["ai_max_token"].as_i.should eq(1200)
      end
    end

    it "falls back to the default for an unparsable integer" do
      # Same "warn on stderr, keep going with the default" shape as the
      # invalid-boolean path, so `.as_i` downstream can never raise.
      with_noir_home("ai_max_token: \"abc\"\n") do |options|
        options["ai_max_token"].as_i.should eq(0)
      end
    end
  end

  # A YAML sequence is the natural spelling for a list of globs or tech
  # names, and `base:` / `probe_header:` in the same file *are* sequences.
  # Untreated, `exclude_path: ["*.py"]` stringified to Crystal's array
  # inspect, which matches no file — the pattern silently excluded nothing.
  describe "CSV_CONFIG_KEYS normalization" do
    it "joins a YAML sequence for exclude_path with commas" do
      body = <<-YAML
        exclude_path:
          - "*.py"
          - "*_test.go"
        YAML
      with_noir_home(body) do |options|
        options["exclude_path"].to_s.should eq("*.py,*_test.go")
      end
    end

    it "normalizes every CSV key, not just exclude_path" do
      body = <<-YAML
        exclude_codes: [404, 500]
        techs: [ruby_sinatra]
        only_techs: [ruby_rails]
        exclude_techs: [php_pure]
        use_taggers: [cors, oauth]
        YAML
      with_noir_home(body) do |options|
        options["exclude_codes"].to_s.should eq("404,500")
        options["techs"].to_s.should eq("ruby_sinatra")
        options["only_techs"].to_s.should eq("ruby_rails")
        options["exclude_techs"].to_s.should eq("php_pure")
        options["use_taggers"].to_s.should eq("cors,oauth")
      end
    end

    it "leaves an existing comma string untouched" do
      with_noir_home("exclude_path: \"*.py,*.rb\"\n") do |options|
        options["exclude_path"].to_s.should eq("*.py,*.rb")
      end
    end

    it "turns an empty sequence into an empty string" do
      with_noir_home("use_taggers: []\n") do |options|
        options["use_taggers"].to_s.should eq("")
      end
    end
  end

  describe "generate_config_file" do
    it "documents only_techs and tls_skip_verify (both are live config keys)" do
      body = ConfigInitializer.new.generate_config_file
      body.should contain("only_techs:")
      body.should contain("tls_skip_verify:")
    end

    it "omits the removed analyze_feign key" do
      # The --analyze-feign flag was dropped when Feign analysis became
      # unconditional; the config key is dead and no longer emitted.
      ConfigInitializer.new.generate_config_file.should_not contain("analyze_feign")
    end

    it "emits only keys that exist in default_options" do
      # Guards against a template line drifting from the option set —
      # a key in the generated file that noir doesn't recognize would
      # silently do nothing for the user who set it.
      ci = ConfigInitializer.new
      defaults = ci.default_options
      YAML.parse(ci.generate_config_file).as_h.each_key do |key|
        defaults.has_key?(key.to_s).should be_true
      end
    end
  end

  describe "setup" do
    it "creates the default config file with 0600 permissions" do
      # The file carries an ai_key field (real provider API keys), so it
      # must not be world-readable on a shared box.
      {% unless flag?(:windows) %}
        dir = File.tempname("noir-perm-spec-")
        Dir.mkdir(dir)
        saved = ENV["NOIR_HOME"]?
        ENV["NOIR_HOME"] = dir
        begin
          ConfigInitializer.new.setup
          path = File.join(dir, "config.yaml")
          File.exists?(path).should be_true
          (File.info(path).permissions.value & 0o777).should eq(0o600)
        ensure
          if s = saved
            ENV["NOIR_HOME"] = s
          else
            ENV.delete("NOIR_HOME")
          end
          FileUtils.rm_rf(dir)
        end
      {% end %}
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

    # `Noir::Home.path` calls `Noir::CLI.die` when neither NOIR_HOME nor HOME
    # is set, and `initialize` used to evaluate it on its first line — above
    # the override branch. So `--config-file ./f.yaml`, the documented escape
    # hatch for exactly that environment (distroless images, `--user`
    # containers, hardened CI runners), died before the override was looked
    # at, leaving no way to run a scan at all.
    #
    # Note what a regression looks like here: the pre-fix code doesn't fail
    # this example, it `exit(1)`s the whole spec process.
    it "reads an override file with neither NOIR_HOME nor HOME set" do
      path = File.tempname("noir-cfg-homeless-")
      File.write(path, "concurrency: 9\n")
      saved_home = ENV["HOME"]?
      saved_noir_home = ENV["NOIR_HOME"]?
      ENV.delete("HOME")
      ENV.delete("NOIR_HOME")

      begin
        options = ConfigInitializer.new(path).read_config
        options["concurrency"].to_s.should eq("9")
      ensure
        ENV["HOME"] = saved_home if saved_home
        ENV["NOIR_HOME"] = saved_noir_home if saved_noir_home
        File.delete?(path)
      end
    end

    # The escape hatch should open, not make the error disappear: with no
    # override there is genuinely nowhere to read from, and the clear
    # "set NOIR_HOME" message is the right answer. `setup` is the part that
    # would otherwise try to `mkdir` a home that can't be resolved, so pin
    # that it still walks the Noir::Home path when there's no override.
    it "still resolves the default config under NOIR_HOME when no override is given" do
      dir = File.tempname("noir-cfg-default-home-")
      Dir.mkdir(dir)
      saved_home = ENV["HOME"]?
      saved_noir_home = ENV["NOIR_HOME"]?
      ENV.delete("HOME")
      ENV["NOIR_HOME"] = dir

      begin
        ConfigInitializer.new.setup
        File.exists?(File.join(dir, "config.yaml")).should be_true
      ensure
        ENV["HOME"] = saved_home if saved_home
        if s = saved_noir_home
          ENV["NOIR_HOME"] = s
        else
          ENV.delete("NOIR_HOME")
        end
        FileUtils.rm_rf(dir)
      end
    end

    # `Noir::Home.path` expands a leading `~` on purpose: a path arriving from
    # a Dockerfile `ENV` / systemd `Environment=` / .env loader never gets the
    # shell's expansion. `--config-file` is fed from the same kinds of place
    # and had no expansion at all, so `~/noir.yaml` resolved to a literal
    # `./~/noir.yaml` under the cwd.
    it "expands a leading ~ in the override path" do
      home = File.tempname("noir-cfg-tilde-home-")
      Dir.mkdir(home)
      saved_home = ENV["HOME"]?
      ENV["HOME"] = home
      File.write(File.join(home, "noir.yaml"), "concurrency: 23\n")

      begin
        options = ConfigInitializer.new("~/noir.yaml").read_config
        options["concurrency"].to_s.should eq("23")
      ensure
        if s = saved_home
          ENV["HOME"] = s
        else
          ENV.delete("HOME")
        end
        FileUtils.rm_rf(home)
      end
    end

    it "falls back to defaults when the override path is a directory" do
      # `File.exists?` is true for a directory, and the `File.read` that
      # followed it sat *outside* the YAML rescue below — so
      # `noir scan ./app --config-file /some/dir` died with a raw Crystal
      # backtrace (`read (...): Is a directory`) before CliValidation could
      # print its one-line "--config-file is not a file".
      dir = File.tempname("noir-config-dir-")
      Dir.mkdir(dir)
      begin
        options = ConfigInitializer.new(dir).read_config
        options["format"].to_s.should eq("plain")
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "falls back to defaults when the override path cannot be read" do
      path = File.tempname("noir-config-noperm-", ".yaml")
      File.write(path, "format: json\n")
      File.chmod(path, 0o000)
      begin
        options = ConfigInitializer.new(path).read_config
        options["format"].to_s.should eq("plain")
      ensure
        File.chmod(path, 0o600)
        File.delete?(path)
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
