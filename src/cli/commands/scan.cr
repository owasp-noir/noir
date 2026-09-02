require "colorize"
require "yaml"
require "../common"
require "../legacy"
require "../../options"
require "../../cli_validation"
require "../../banner"
require "../../models/noir"
require "../../techs/techs"
require "../../llm/cache"
require "../../llm/prompt_overrides"

# `noir scan [paths...] [flags]`
#
# Discovers endpoints across one or more code bases. Positional paths
# augment any `-b PATH` flags so both v0 and v1 invocation styles work:
#
#   noir scan ./app                 # v1 positional
#   noir scan ./api ./worker        # v1 multi-path positional
#   noir -b ./app                   # v0 (router default-routes to scan)
#   noir scan -b ./app --passive    # v1 explicit + flags
module Noir::CLI::ScanCommand
  # ANSI 256-color orange used for the protocol-missing warning. Kept
  # as a named constant so the call site reads as "warning color"
  # rather than a bare magic number.
  WARNING_COLOR = Colorize::Color256.new(208)

  def self.run(argv : Array(String))
    # Stage ARGV through OptionParser (positional path discovery happens
    # inside `run_options_parser`). Dup `argv` upfront because callers
    # commonly pass ARGV itself, which we are about to clear. The v0
    # deliver/probe flag tokens (`--send-req`, `--use-matchers`, etc.)
    # are rewritten to their v1 equivalents *before* the parser runs,
    # so the LEGACY surface never appears in `scan -h` and the parser
    # itself only needs to know about one set of names.
    args_copy = Noir::CLI::Legacy.translate_flag_aliases(argv.dup)
    saved = ARGV.dup
    begin
      ARGV.clear
      ARGV.concat(args_copy)

      noir_options = run_options_parser
    ensure
      ARGV.clear
      ARGV.concat(saved)
    end

    # `args_copy`, not `noir_options`, is what says which settings the user
    # typed on this command line: by the time the parser returns, a
    # config-file value and a CLI flag are the same entry in the same hash.
    execute(noir_options, args_copy)
  end

  # Long-flag tokens present on the command line, with `--flag=value`
  # reduced to `--flag`. The only question asked of it is "did the user
  # type this flag?", which is why the values are dropped.
  def self.cli_flag_names(argv : Array(String)) : Set(String)
    names = Set(String).new
    argv.each do |arg|
      next unless arg.starts_with?("-")
      names << (arg.index('=') ? arg.split("=", 2)[0] : arg)
    end
    names
  end

  private def self.execute(noir_options : Hash(String, YAML::Any), argv : Array(String))
    cli_flags = cli_flag_names(argv)

    apply_cache_flags(noir_options)
    apply_prompt_overrides(noir_options)
    normalize_url!(noir_options)
    normalize_probe_via!(noir_options)
    validate_url_dependent_flags(noir_options, cli_flags)
    validate_exclude_path!(noir_options, argv)
    validate_options!(noir_options)

    if noir_options["nolog"] == false
      Noir::Banner.print
    end

    run_scan(noir_options)
  end

  private def self.apply_cache_flags(noir_options : Hash(String, YAML::Any))
    LLM::Cache.disable if noir_options["cache_disable"] == true

    return unless noir_options["cache_clear"] == true

    begin
      outcome = LLM::Cache.clear
      # Suppress the status line under --no-log ("Show only results"):
      # every other scan log line respects it, and this one would
      # otherwise leak into a result stream a script expects to be
      # clean. The clear itself still happens — only the message is
      # gated. The runner's logger isn't built yet at this point, so
      # gate on the raw option rather than routing through it.
      unless noir_options["nolog"] == true
        msg = "CACHE: Cleared #{outcome.deleted} entries."
        msg += " (#{outcome.failed} failed)" if outcome.failed > 0
        STDERR.puts msg
      end
    rescue
      # Cache may not be initialized yet; best-effort clear.
    end
  end

  PROMPT_OVERRIDE_SETTERS = {
    "override_filter_prompt"         => ->(v : String) { LLM::PromptOverrides.filter_prompt = v },
    "override_analyze_prompt"        => ->(v : String) { LLM::PromptOverrides.analyze_prompt = v },
    "override_bundle_analyze_prompt" => ->(v : String) { LLM::PromptOverrides.bundle_analyze_prompt = v },
    "override_llm_optimize_prompt"   => ->(v : String) { LLM::PromptOverrides.llm_optimize_prompt = v },
  }

  private def self.apply_prompt_overrides(noir_options : Hash(String, YAML::Any))
    PROMPT_OVERRIDE_SETTERS.each do |key, setter|
      setter.call(noir_options[key].to_s) if noir_options.has_key?(key)
    end
  end

  private def self.normalize_url!(noir_options : Hash(String, YAML::Any))
    url = noir_options["url"].to_s
    return if url.empty?

    # Protocol auto-fill when the user typed a bare host like
    # `-u example.com`. The scheme check below then re-runs against
    # the prepended form so a bare hostname falls through into the
    # http/https-only validation cleanly.
    unless url.includes?("://")
      STDERR.puts "WARNING: The protocol (http or https) is missing in the URL '#{url}'. Defaulting to 'https://'.".colorize(WARNING_COLOR)
      url = "https://#{url}"
      noir_options["url"] = YAML::Any.new(url)
    end

    # `-u` is the base URL that gets prepended to every discovered
    # path. Only http(s) make sense here — other schemes (file://,
    # ftp://, …) were silently concatenated pre-fix and produced
    # nonsense URLs like `file:///etc/passwd/sign`. Reject early.
    lowered = url.downcase
    unless lowered.starts_with?("http://") || lowered.starts_with?("https://")
      Noir::CLI.die("-u/--url must use http:// or https:// (got '#{url}').")
    end

    # Validate an explicit port at parse time. A non-numeric port
    # (`-u http://host:por`) otherwise survives until the first probe and
    # crashes deep in the socket layer with an opaque error.
    begin
      parsed = URI.parse(url)

      if host_problem = host_error(parsed.host)
        Noir::CLI.die("-u/--url #{host_problem} in #{url.inspect}. Expected a base URL like http://localhost:3000.")
      end

      if port = parsed.port
        unless (1..65535).includes?(port)
          Noir::CLI.die("-u/--url port #{port} is out of range (1-65535) in '#{url}'.")
        end
      end
    rescue ex : URI::Error
      Noir::CLI.die("-u/--url has an invalid port in '#{url}' (#{ex.message}). The port must be numeric, e.g. http://host:8080.")
    end

    # Strip `?query` and `#fragment` from the base URL — they're
    # only valid at the end of a URL, so concatenating an endpoint
    # path after them produces a malformed URL
    # (`http://x?foo=bar/sign`). The user almost never meant to put
    # them on the base; warn and drop them.
    if (q = url.index('?')) || (f = url.index('#'))
      cut = [q, f].compact.min
      stripped = url[0...cut]
      dropped = url[cut..]
      STDERR.puts "WARNING: -u/--url should be a base URL — query string / fragment '#{dropped}' would corrupt the per-endpoint URL. Stripping.".colorize(WARNING_COLOR)
      noir_options["url"] = YAML::Any.new(stripped)
    end
  end

  # Why `-u` needs an authority, not just a scheme: it is the *base* URL
  # every discovered path is appended to. `URI.parse` is happy without a
  # host — `-u http://` parses with an empty one — and the concatenation
  # then promotes the first discovered path segment to the authority, so
  # `/a` becomes `http://a`. With `--probe` or `--status-codes` that
  # fires real HTTP requests at a host the user never named.
  #
  # Whitespace and control characters are rejected for the same reason
  # `normalize_probe_via!` rejects a missing host: `-u "not a url"` and
  # `-u $'http://a\nb/'` are accepted today and baked into every endpoint
  # of the JSON/OAS/Postman output as an unusable URL.
  #
  # Returns nil when the host is usable, otherwise the reason (phrased to
  # slot into the `-u/--url <reason> in <url>` message).
  def self.host_error(host : String?) : String?
    return "has no host" if host.nil? || host.empty?
    if host.each_char.any? { |c| c.whitespace? || c.control? }
      return "has whitespace or control characters in the host"
    end
    nil
  end

  # `--probe-via` is handed to Crest as a `p_addr` / `p_port` pair, and
  # Crest's `set_proxy!` does `return unless p_addr && p_port` — so any
  # value that doesn't yield BOTH a host and a port made it drop the proxy
  # and send the probe *directly to the target instead*, with no error.
  # That is worse than a plain misconfiguration: `SendWithProxy` also
  # forces an insecure TLS context (correct when talking to an
  # intercepting proxy's own cert), so the fall-through shipped
  # `--probe-header` credentials to the real target with certificate
  # verification off, while the user believed the traffic was sitting in
  # Burp.
  #
  # Two shapes hit it, both of them things users actually type:
  #   `--probe-via 127.0.0.1:8080`   → URI#host is nil (curl -x accepts this)
  #   `--probe-via http://burp.local` → URI#port is nil
  private def self.normalize_probe_via!(noir_options : Hash(String, YAML::Any))
    probe_via = noir_options["probe_via"]?.try(&.to_s) || ""
    return if probe_via.empty?

    # Bare `host:port` is the form `curl -x` and the `HTTP_PROXY` env var
    # take, so accept it rather than rejecting a reasonable habit. An HTTP
    # proxy is the only thing this flag ever points at, hence http://.
    unless probe_via.includes?("://")
      probe_via = "http://#{probe_via}"
      noir_options["probe_via"] = YAML::Any.new(probe_via)
    end

    lowered = probe_via.downcase
    unless lowered.starts_with?("http://") || lowered.starts_with?("https://")
      Noir::CLI.die("--probe-via must use http:// or https:// (got '#{probe_via}').")
    end

    begin
      parsed = URI.parse(probe_via)
    rescue ex : URI::Error
      Noir::CLI.die("--probe-via is not a valid proxy URL: '#{probe_via}' (#{ex.message}).")
    end

    host = parsed.host
    if host.nil? || host.empty?
      Noir::CLI.die("--probe-via has no host in '#{probe_via}'. Expected proxy_host:port, e.g. --probe-via http://127.0.0.1:8080.")
    end

    # The port is required, not defaulted. Guessing would silently pick
    # the wrong peer: 8080 (Burp/ZAP's default) and 80 (the scheme
    # default) are both plausible readings of `http://burp.local`, and
    # picking either one for the user is how the original bug felt from
    # the outside — traffic going somewhere they didn't ask for.
    port = parsed.port
    if port.nil?
      Noir::CLI.die("--probe-via needs an explicit proxy port in '#{probe_via}' — otherwise probes would silently bypass the proxy and hit the target directly. Burp/ZAP default to 8080, e.g. --probe-via #{parsed.scheme}://#{host}:8080.")
    end

    unless (1..65535).includes?(port)
      Noir::CLI.die("--probe-via port #{port} is out of range (1-65535) in '#{probe_via}'.")
    end
  end

  # A url-dependent setting the user did NOT type on this command line
  # came from the config file, which cannot know whether this particular
  # run has a target URL. Aborting on it bricked every URL-less scan for
  # anyone with `status_codes:`/`probe:` in their config — a documented
  # key the generated template lists — and blamed a flag they never
  # typed. A CLI flag stays a hard usage error; a config value is
  # downgraded to a warning and switched off for this run.
  private def self.require_url_or_disable!(noir_options : Hash(String, YAML::Any),
                                           cli_flags : Set(String),
                                           flag : String,
                                           key : String,
                                           example : String,
                                           disabled : YAML::Any)
    if cli_flags.includes?(flag)
      Noir::CLI.die("#{flag} needs a target URL. Pass it with -u/--url, e.g. `#{example}`.")
    end

    STDERR.puts "WARNING: config key `#{key}` (#{flag}) needs a target URL; none was given, so it is disabled for this scan. Pass one with -u/--url, or drop `#{key}` from the config file.".colorize(WARNING_COLOR)
    noir_options[key] = disabled
  end

  private def self.validate_url_dependent_flags(noir_options : Hash(String, YAML::Any),
                                                cli_flags : Set(String))
    url = noir_options["url"].to_s

    if url.empty?
      if noir_options["status_codes"] == true
        require_url_or_disable!(noir_options, cli_flags,
          flag: "--status-codes", key: "status_codes",
          example: "noir scan ./app --status-codes -u http://localhost:3000",
          disabled: YAML::Any.new(false))
      end

      # `--probe` and `--probe-via` both fire HTTP requests against
      # `endpoint.url`, which is just the discovered path (e.g. `/sign`)
      # until `-u/--url` prepends a base. Without `-u` the request URL is
      # malformed and Crest raises — but the SendReq / SendWithProxy
      # delivery loops catch + log to debug level only, so the user sees
      # the normal JSON output with zero requests sent and no warning.
      # Fail early instead.
      if noir_options["probe"]? == YAML::Any.new(true)
        require_url_or_disable!(noir_options, cli_flags,
          flag: "--probe", key: "probe",
          example: "noir scan ./app --probe -u http://localhost:3000",
          disabled: YAML::Any.new(false))
      end

      probe_via = noir_options["probe_via"]?.try(&.to_s) || ""
      unless probe_via.empty?
        require_url_or_disable!(noir_options, cli_flags,
          flag: "--probe-via", key: "probe_via",
          example: "noir scan ./app --probe-via #{probe_via} -u http://localhost:3000",
          disabled: YAML::Any.new(""))
      end

      unless noir_options["exclude_codes"].to_s.empty?
        require_url_or_disable!(noir_options, cli_flags,
          flag: "--exclude-codes", key: "exclude_codes",
          example: "noir scan ./app --exclude-codes 404,500 -u http://localhost:3000",
          disabled: YAML::Any.new(""))
      end
    end

    # Runs whether or not a URL was given: a malformed value is a typo
    # worth reporting even on the config-sourced path above (which leaves
    # the key empty, so this loop then has nothing to check).
    exclude_codes = noir_options["exclude_codes"].to_s
    return if exclude_codes.empty?

    exclude_codes.split(",").each do |code|
      code.strip.to_i
    rescue
      Noir::CLI.die("--exclude-codes only accepts comma-separated numbers; got '#{code}'.")
    end
  end

  # `--exclude-path` patterns are only interpreted deep inside the
  # detector's file walk, so a malformed one either aborts the scan
  # halfway (an unterminated `[`, which at least reports itself) or
  # silently matches nothing — `'*.{rb'`, `'{'`, `''` and `'  '` were all
  # accepted and excluded exactly zero files, which from the outside is
  # indistinguishable from an exclusion that worked. Validate the whole
  # list at parse time instead, before a single file is read.
  private def self.validate_exclude_path!(noir_options : Hash(String, YAML::Any),
                                          argv : Array(String))
    if blank_exclude_path_arg?(argv)
      Noir::CLI.die("--exclude-path needs a glob pattern; the value given is empty.")
    end

    raw = noir_options["exclude_path"]?.try(&.to_s) || ""
    return if raw.empty?

    raw.split(",").each do |entry|
      # Normalized exactly the way `Noir::ExcludePath` normalizes it, so
      # what is validated is what will run.
      pattern = entry.strip.gsub('\\', '/')
      if pattern.empty?
        Noir::CLI.die("--exclude-path contains a blank pattern in #{raw.inspect}; every comma-separated entry must be a glob.")
      end

      if problem = glob_error(pattern)
        Noir::CLI.die("--exclude-path contains an invalid glob pattern (#{problem}): #{pattern.inspect}.")
      end
    end
  end

  # `--exclude-path ''` and `--exclude-path=` both collapse to the same
  # empty string the option carries when it was never passed at all (and
  # `exclude_path: ""` is in the generated config template), so the fully
  # blank case can only be read off argv.
  private def self.blank_exclude_path_arg?(argv : Array(String)) : Bool
    argv.each_with_index do |arg, i|
      if arg == "--exclude-path"
        value = argv[i + 1]?
        # A missing value is OptionParser's error to report, not ours.
        return true if value && value.strip.empty?
      elsif arg.starts_with?("--exclude-path=")
        return true if arg.split("=", 2)[1].strip.empty?
      end
    end
    false
  end

  # Returns nil for a usable glob, otherwise the reason it is broken.
  #
  # `File.match?` parses the pattern itself, so character-class errors
  # come back from Crystal with its own wording. Brace groups it accepts
  # and then never matches (`*.{rb` matches nothing at all), so the
  # `{`/`}` balance is checked here — skipping over character classes,
  # inside which a brace is an ordinary character.
  def self.glob_error(pattern : String) : String?
    depth = 0
    in_class = false
    pattern.each_char do |char|
      if in_class
        in_class = false if char == ']'
      elsif char == '['
        in_class = true
      elsif char == '{'
        depth += 1
      elsif char == '}'
        depth -= 1
        return "unmatched `}`" if depth < 0
      end
    end
    return "unterminated `{` group" if depth > 0

    begin
      File.match?(pattern, "noir")
      nil
    rescue ex : File::BadPatternError
      ex.message || "invalid pattern"
    end
  end

  private def self.validate_options!(noir_options : Hash(String, YAML::Any))
    Noir::CliValidation.validate!(noir_options)
  rescue e : Noir::CliValidation::Error
    Noir::CliValidation.exit_with_error(e.message || "Invalid options.")
  end

  # An AI provider is "active" when --ai-provider was set AND either
  # --ai-model was also set OR the provider is an ACP target (which
  # supplies its own default model).
  private def self.ai_provider_active?(options : Hash(String, YAML::Any)) : Bool
    provider = options["ai_provider"].to_s
    return false if provider.empty?

    !options["ai_model"].to_s.empty? || provider.downcase.starts_with?("acp:")
  end

  # Names everything the scan did not cover — an analyzer that raised, files
  # it could not read or parse, a directory the walk could not list, an
  # export that never landed, a passive rule set that loaded nothing — so a
  # degraded scan says so instead of reporting what survived as the whole
  # story. Laid out like the detected-techs list above it (`├──` / `└──`),
  # because it answers the same question: which parts of the scan actually
  # processed what.
  private def self.report_coverage_gaps(logger : NoirLogger,
                                        failures : Array(AnalyzerFailure),
                                        scope : String)
    return if failures.empty?

    plural = failures.size == 1 ? "gap" : "gaps"
    logger.warning "#{failures.size} coverage #{plural} reported#{scope}; results may be incomplete."
    failures.each_with_index do |failure, index|
      prefix = index < failures.size - 1 ? "├──" : "└──"
      logger.sub "#{prefix} #{failure.tech}: #{failure.message}"
    end
  end

  # Exit code for a scan that produced its report.
  #
  # Exit 2 rather than 1 so a CI gate can tell "scan ran, coverage
  # incomplete" from the usage/validation errors that already exit 1.
  #
  # `degraded` used to read `!app.analyzer_failures.empty?` when that list
  # held tech-level analyzer failures and nothing else, so `--strict` — whose
  # documented contract is "exit 2 if any analyzer failed *or skipped a
  # file*" — reported green on a scan that lost a whole subtree to an
  # unlistable directory, dropped every symlinked package, exported nothing,
  # or ran zero passive rules. Every one of those now feeds the same list, so
  # the test is unchanged and finally means what it says.
  def self.scan_exit_code(app : NoirRunner, app_diff : NoirRunner?) : Int32
    degraded = !app.analyzer_failures.empty?
    if diff_app = app_diff
      degraded ||= !diff_app.analyzer_failures.empty?
    end

    degraded && any_to_bool(app.options["strict"]?) ? 2 : 0
  end

  private def self.run_scan(noir_options : Hash(String, YAML::Any))
    app = NoirRunner.new noir_options
    start_time = Time.instant

    app.logger.debug("Start Debug mode")
    app.logger.debug("Noir version: #{Noir::VERSION}")
    app.logger.debug("Noir options from arguments:")
    noir_options.each do |k, v|
      app.logger.debug_sub("#{k}: #{v}")
    end

    app.logger.debug "Initialized Options:"
    app.options.each do |k, v|
      app.logger.debug_sub "#{k}: #{v}"
    end

    app_diff = nil
    unless noir_options["diff"].to_s.empty?
      diff_path = noir_options["diff"].to_s
      # Validate the diff target exists — without this, a misspelled
      # `--diff-path` silently treats every current endpoint as
      # "added" (because the missing directory analyzes to zero
      # endpoints), which is indistinguishable from "we made huge
      # changes" in CI diff pipelines.
      unless File.exists?(diff_path)
        Noir::CLI.die("--diff-path does not exist: #{diff_path}")
      end
      unless File.directory?(diff_path)
        Noir::CLI.die("--diff-path is not a directory: #{diff_path}")
      end

      diff_options = noir_options.dup
      diff_options["base"] = YAML::Any.new([YAML::Any.new(diff_path)])
      # `noir_options.dup` already carries over the parent's `nolog`
      # setting, so --no-log applies to both scans uniformly.
      # The previous shape force-set nolog=false for the diff side,
      # which mixed diff-scan progress (banner, "Optimizing
      # endpoints", "Found N endpoints") into the JSON stdout when
      # the user explicitly asked for quiet output.

      # Disable PROBE/EXPORT on the diff side. The diff scan is a
      # detection-only pass — its sole purpose is to enumerate the
      # *old* endpoints so the diff report can name what changed.
      # Pre-fix, `--probe --diff-path X` fired HTTP requests against
      # every base endpoint AND every old endpoint (so
      # unchanged-but-present URLs got hit twice and removed-only
      # URLs got hit once), and `--export-es --diff-path X` pushed
      # the stale catalog into the index alongside the current one.
      # Both surprised users running diff scans in CI.
      diff_options["probe"] = YAML::Any.new(false)
      diff_options["probe_via"] = YAML::Any.new("")
      diff_options["export_es"] = YAML::Any.new("")
      diff_options["export_webhook"] = YAML::Any.new("")

      app_diff = NoirRunner.new diff_options
      app.logger.info "Running Noir with Diff mode."
    end

    app.logger.loading "Detecting technologies in the base directory." do
      app.detect
    end

    analysis_message = "Starting code analysis."

    if app.techs.empty?
      app.logger.warning "No technologies detected."
      app.logger.sub "➔ If you know the technology, use the -t flag to specify it."
      app.logger.sub "➔ Browse the supported tech list with `noir list techs`."
      if !app.options["url"].to_s.empty?
        app.logger.info "Falling back to file-based analysis because -u was set."
      elsif ai_provider_active?(app.options)
        app.logger.info "Falling back to AI-based analysis because --ai-provider was set."
      elsif FileAnalyzer.url_independent_hooks?
        # No tech analyzer will run, but the url-independent file hooks
        # (GraphQL operation documents) recognise endpoints from file
        # syntax rather than by matching `-u`, so the analysis pass still
        # has work to do. Bailing out here made a code base whose only
        # surface is a `.graphql`/`.gql` operation document report zero
        # endpoints on a plain `noir scan ./app`, even though the analyzer
        # layer had already been fixed to run those hooks without `-u`.
        # FunctionalTester drives `detect`/`analyze` directly, so this
        # CLI-only gate slipped past the functional spec that asserts the
        # endpoint is found on a default scan.
        app.logger.info "Falling back to file-based analysis."
      elsif app.passive_results.size > 0
        app.logger.info "Noir found #{app.passive_results.size} passive results."
        # The detection walk still ran, so it can still have lost a subtree
        # — and this branch returns without ever reaching the `--strict`
        # check at the bottom of the method.
        report_coverage_gaps(app.logger, app.analyzer_failures, "")
        app.report
        exit(scan_exit_code(app, app_diff))
      else
        # Structured formats still get a report call on an empty scan, so
        # downstream consumers receive a valid empty document rather than
        # nothing. Which formats those are is declared on the builder
        # (`structured: true`) — see `Noir::OutputFormats::STRUCTURED_NAMES`.
        report_coverage_gaps(app.logger, app.analyzer_failures, "")
        if Noir::OutputFormats.structured?(app.options["format"].to_s)
          app.report
        end
        # "No technologies detected" is exactly the shape an unlistable or
        # unreadable base directory produces, so this is the branch where a
        # silent loss is most likely and least visible.
        exit(scan_exit_code(app, app_diff))
      end
    else
      app.logger.success "Detected #{app.techs.size} technologies."

      # Alias-resolved once, then matched by identity. `--exclude-techs`
      # used to ask `similar_to_tech(entry).includes?(tech)`, a substring
      # test that also dropped every tech whose name is a prefix of the
      # excluded one — `--exclude-techs python_django_ninja` took
      # `python_django` with it. See `NoirTechs.resolve_tech_list`.
      exclude_techs = NoirTechs.resolve_tech_list(app.options["exclude_techs"].to_s).to_set
      app.techs.each_with_index do |tech, index|
        is_excluded = exclude_techs.includes?(tech)
        prefix = index < app.techs.size - 1 ? "├──" : "└──"
        status = is_excluded ? " (skip)" : ""
        app.logger.sub "#{prefix} #{tech}#{status}"
      end

      app.techs = app.techs.reject { |tech| exclude_techs.includes?(tech) }
      analysis_message = "Starting code analysis based on the detected technologies."
    end

    app.logger.loading analysis_message do
      app.analyze
    end
    app.logger.success "Identified #{app.endpoints.size} endpoints in total."
    report_coverage_gaps(app.logger, app.analyzer_failures, "")

    elapsed = Time.instant - start_time
    app.logger.info "Scan completed in #{(elapsed.total_milliseconds / 1000.0).round(4)} s."

    if app_diff.nil?
      app.logger.info "Generating Report."
      app.report
    else
      app.logger.info "Diffing base and diff codebases."
      # Kept even though `LocatorKeys.reset` now runs at the top of each
      # phase: this is a real codebase boundary, and `clear_all` is the only
      # thing that also drops `Process`-lifetime slots a library caller
      # declared. It does not reset `scan_base_paths` — `NoirRunner#detect`
      # re-publishes those before anything walks a file, which is why the
      # first codebase's roots have never been observable here.
      locator = CodeLocator.instance
      locator.clear_all
      app_diff.detect
      app_diff.analyze
      # The diff is computed against the old codebase's endpoint list, so an
      # analyzer that died over there turns unscanned routes into phantom
      # "added" entries. Named separately from the base scan's failures —
      # the two scans have different code, and only one of them is the one
      # the user is about to act on.
      report_coverage_gaps(app.logger, app_diff.analyzer_failures, " in the --diff-path codebase")

      app.logger.info "Generating Diff Report."
      app.diff_report(app_diff)
    end

    # After the report, never before: a degraded scan still has results, and
    # the point of `--strict` is to flag them, not to withhold them.
    code = scan_exit_code(app, app_diff)
    exit(code) if code != 0
  rescue e : Noir::InvalidExcludePathError
    # Raised from the detector's file walk once a malformed --exclude-path
    # glob is actually reached. Without this the process printed a raw
    # Crystal backtrace from a dead fiber and still exited 0.
    Noir::CLI.die(e.message || "--exclude-path contains an invalid glob pattern.")
  end
end
