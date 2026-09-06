require "../detector/detector.cr"
require "../analyzer/analyzer.cr"
require "../tagger/tagger.cr"
require "../passive_scan/rules.cr"
require "../deliver/*"
require "../output_builder/*"
require "../optimizer/llm_optimizer.cr"
require "../llm/cache.cr"
require "../ai_context/augmentor.cr"
require "../mobile/linker.cr"
require "./analyzer_failure.cr"
require "./skipped_files.cr"
require "./endpoint.cr"
require "./logger.cr"
require "../utils/*"
require "json"
require "yaml"

class NoirRunner
  @options : Hash(String, YAML::Any)
  @techs : Array(String)
  @endpoints : Array(Endpoint)
  @logger : NoirLogger
  @probe_via : String
  @probe : Bool
  @export_es : String
  @export_webhook : String
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @no_spinner : Bool
  @concurrency : Int32
  @config_file : String
  @passive_scans : Array(PassiveScan)
  @passive_results : Array(PassiveScanResult)
  # Tech analyzers that raised during the last `analyze`, plus the files
  # individual analyzers skipped. Filled by `analysis_endpoints`.
  @tech_failures = [] of AnalyzerFailure
  # Coverage the scan lost outside the analysis pass: directories the walk
  # could not list, files it could not read, exports that never landed, a
  # passive rule set that loaded nothing. Snapshotted from
  # `Noir::SkippedFiles` at the end of each phase rather than read live, so
  # the diff runner's own detect pass cannot wipe this runner's findings.
  @scan_failures = [] of AnalyzerFailure

  getter options, techs, endpoints, logger, passive_results

  # Everything this scan did not cover, from any phase. Empty is the positive
  # statement "the scan read what it was pointed at and delivered what it was
  # asked to", which is what tells a degraded scan from a clean one — and what
  # `--strict` exits 2 on.
  def analyzer_failures : Array(AnalyzerFailure)
    @scan_failures + @tech_failures
  end

  def initialize(options)
    @options = options
    @config_file = @options["config_file"].to_s
    # `@noir_home = Noir::Home.path` used to run here. Nothing ever read the
    # field, but `Noir::Home.path` dies when neither NOIR_HOME nor HOME is
    # set — so every scan in a HOME-less environment (distroless image,
    # `--user` container, hardened CI runner) died on this line even with an
    # explicit `--config-file`. The callers that genuinely need the home
    # directory (LLM cache, `-f html` template, passive rules) resolve it
    # themselves, at the point of use.
    @passive_scans = [] of PassiveScan
    @passive_results = [] of PassiveScanResult

    # `--config-file PATH` is applied earlier by ConfigInitializer
    # (the CLI layer hands it in as the override path), so the
    # file's contents are already merged into `options` before CLI
    # flags run. Re-merging here used to *re-overwrite* every CLI
    # flag the user had just set — a `noir --probe -u http://x
    # --config-file probe-off.yaml` invocation silently dropped
    # `--probe` because the file's `probe: false` won the merge.
    # Library callers that bypass the CLI can pre-merge YAML
    # themselves before constructing NoirRunner.

    @techs = [] of String
    @endpoints = [] of Endpoint
    @probe_via = @options["probe_via"].to_s
    @probe = any_to_bool(@options["probe"])
    @export_es = @options["export_es"].to_s
    @export_webhook = @options["export_webhook"].to_s
    @is_debug = any_to_bool(@options["debug"])
    @is_verbose = any_to_bool(@options["verbose"])
    @is_color = any_to_bool(@options["color"])
    @is_log = any_to_bool(@options["nolog"])
    @no_spinner = any_to_bool(@options["no_spinner"])
    @concurrency = @options["concurrency"].to_s.to_i

    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log, @no_spinner

    # The LLM disk cache swallows its own IO failures and has no logger of
    # its own (it is a module of class methods reached from several
    # layers). Hand it this run's logger so those failures follow `--debug`
    # onto STDERR like every other Noir diagnostic — they used to be
    # written to Crystal's global `Log`, whose backend is STDOUT.
    LLM::Cache.logger = @logger

    if ai_context_enabled?
      @options["include_callee"] = YAML::Any.new(true)
    end

    if any_to_bool(@options["passive_scan"])
      @logger.info "Passive scanner enabled."

      custom_rule_paths = @options["passive_scan_path"].as_a

      # Only bootstrap/refresh the bundled ruleset when this run will
      # actually read it. With `--passive-scan-path` the very next log line
      # says the bundled rules are skipped, yet this used to `git clone`
      # the upstream rules repository into $NOIR_HOME and then `git fetch`
      # it over the network — an unasked-for download, and a hang in an
      # air-gapped or credential-less environment, for rules the run then
      # threw away.
      if custom_rule_paths.empty? && !any_to_bool(@options["passive_scan_no_update_check"])
        # Initialize rules if they don't exist
        PassiveRulesUpdater.initialize_rules(@logger)

        # Check for updates (auto-update if enabled)
        auto_update = any_to_bool(@options["passive_scan_auto_update"])
        PassiveRulesUpdater.check_for_updates(@logger, auto_update)
      end

      if !custom_rule_paths.empty?
        @logger.sub "├── Using custom passive rules only (bundled rules skipped)."
        # Concatenate rules from every passive_scan_path. The previous
        # assignment (`@passive_scans = NoirPassiveScan.load_rules …`)
        # inside the loop silently dropped every path except the last
        # one whenever the user passed multiple --passive-scan-path
        # entries.
        custom_rule_paths.each do |rule_path|
          @passive_scans.concat(NoirPassiveScan.load_rules(rule_path.to_s, @logger))
        end
        # `load_rules` deduplicates within one directory; the same rule id
        # arriving from two different `--passive-scan-path` entries has to
        # be caught here or every one of its findings is reported twice.
        @passive_scans = NoirPassiveScan.reject_duplicate_ids(@passive_scans, @logger)
      else
        # Resolve the effective rules path — prefers the user-managed
        # `$NOIR_HOME/passive_rules` when populated, falls back to the
        # image-baked snapshot at `/opt/noir/passive_rules` (present
        # in the official Docker image) so `-P` works out of the box
        # without network/git.
        rules_dir = PassiveRulesUpdater.effective_rules_path
        @logger.sub "├── Using default passive rules (#{rules_dir})."
        @passive_scans = NoirPassiveScan.load_rules rules_dir, @logger
      end
    end
  end

  def detect
    base_paths = options["base"].as_a.map(&.to_s)
    # Publish the scan roots before anything walks a file: the shared
    # parser layer relativises convention filters against them (see
    # `CodeLocator#base_relative`).
    CodeLocator.instance.scan_base_paths = base_paths
    detected_techs = detect_techs base_paths, options, @passive_scans, @logger
    @techs = detected_techs[0]
    @passive_results = detected_techs[1]

    # `-P` with an empty rule set is a guaranteed false negative that is
    # indistinguishable from a clean scan: zero rules produce zero findings.
    # Recorded here rather than in `load_rules` because rules are loaded in
    # the constructor, before `detect_techs` clears the scan-phase gaps.
    if any_to_bool(@options["passive_scan"]) && @passive_scans.empty?
      Noir::SkippedFiles.record_gap(
        Noir::SkippedFiles::PASSIVE_SCAN_SCOPE,
        "passive scan requested but 0 rules were loaded; no passive findings can be reported"
      )
    end

    @scan_failures = Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Scan)

    # Build extension index eagerly after file_map is finalized
    # to avoid concurrent lazy-build race in analyzers
    CodeLocator.instance.build_extension_index

    if @is_debug
      @logger.debug("CodeLocator Table:")
      locator = CodeLocator.instance
      locator.show_table

      @logger.debug("Detected Techs: #{@techs}")
      @logger.debug("Passive Results: #{@passive_results}")
    end
  end

  def analyze
    # Cleared before the pass, not merely appended to. Diff mode builds a
    # second runner, but an embedder can call `analyze` twice on one runner —
    # and a failure list carrying the previous scan's entries would report a
    # clean run as degraded (and, under `--strict`, fail the build) forever
    # after. Same class of leak as the options-hash one
    # `apply_cfml_components_only!` documents.
    @tech_failures.clear
    @endpoints = analysis_endpoints options, @techs, @logger, @tech_failures

    # Use the new optimizer module
    optimizer = LLMEndpointOptimizer.new(@logger, @options)
    @endpoints = optimizer.optimize(@endpoints)

    # Link mobile deep-link endpoints to their handler source (callees +
    # handler code_path) so taggers and AI context see the real surface.
    @endpoints = NoirMobileLinker.apply(@endpoints, @logger)

    # Set status code
    if any_to_bool(@options["status_codes"]) || !@options["exclude_codes"].to_s.empty?
      @endpoints = StatusCodeProbe.new(@options, @logger).apply(@endpoints)
    end

    # Run tagger
    if any_to_bool(@options["all_taggers"])
      @logger.success "Running all taggers."
      NoirTaggers.run_tagger @endpoints, @options, "all"
      if @is_debug
        NoirTaggers.taggers.each do |tagger|
          @logger.debug "Tagger: #{tagger.key} (#{tagger.name})"
        end
      end
    elsif !@options["use_taggers"].to_s.empty?
      @logger.success "Running #{@options["use_taggers"]} taggers."
      NoirTaggers.run_tagger @endpoints, @options, @options["use_taggers"].to_s
    elsif ai_context_enabled?
      @logger.success "Running AI-context taggers."
      NoirTaggers.run_tagger @endpoints, @options, "all"
    elsif @options["format"].to_s == "only-tag"
      # `-f only-tag` has nothing to print unless a tagger populated tags.
      # Without this, the format silently produced empty output unless the
      # user also passed -T/--use-taggers — an easy trap. Imply all taggers
      # when no explicit tagger option was given.
      @logger.success "Running all taggers (implied by -f only-tag)."
      NoirTaggers.run_tagger @endpoints, @options, "all"
    end

    if ai_context_enabled?
      @logger.success "Building aggregated AI context."
      NoirAIContext.apply(@endpoints)
      apply_ai_context_feature_filter
    end

    # Run deliver
    deliver

    # Deliver runs inside the analysis pass but records into the scan phase,
    # so re-snapshot now that it is done. A full replace rather than a
    # concat: `analyze` can be called twice on one runner, and appending
    # would report the detect-phase gaps once per call.
    @scan_failures = Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Scan)
  end

  private def ai_context_enabled? : Bool
    any_to_bool(@options["ai_context"]?)
  end

  # `--ai-context=guards,sinks` narrows the user's view. The
  # augmentor populates every bucket anyway (patterns aren't scoped
  # by category), so we trim after the fact. Json/yaml/sarif/postman/
  # oas serialize the struct directly, which is why this trim has
  # to happen at the data layer — the plain-text builder's filter
  # alone left structured outputs leaking every bucket.
  private def apply_ai_context_feature_filter
    raw = @options["ai_context_features"]?.try(&.to_s) || ""
    features = NoirAIContext.parse_feature_set(raw)
    NoirAIContext.apply_feature_filter(@endpoints, features)
  end

  def deliver
    unless @probe_via.empty?
      @logger.info "Probing endpoints through proxy #{@probe_via}."
      deliver = SendWithProxy.new(@options)
      deliver.run(@endpoints)
    end

    if @probe != false
      @logger.info "Probing endpoints directly."
      deliver = SendReq.new(@options)
      deliver.run(@endpoints)
    end

    unless @export_es.empty?
      @logger.info "Exporting endpoints to Elasticsearch."
      deliver = SendElasticSearch.new(@options)
      deliver.run(@endpoints, @export_es)
    end

    unless @export_webhook.empty?
      @logger.info "Exporting endpoints to webhook #{@export_webhook}."
      deliver = SendWebhook.new(@options)
      deliver.run(@endpoints, @export_webhook)
    end
  end

  def diff_report(diff_app)
    builder = OutputBuilderDiff.new @options

    case options["format"]
    when "yaml"
      builder.print_yaml @endpoints, diff_app
    when "json"
      builder.print_json @endpoints, diff_app
    when "toml"
      builder.print_toml @endpoints, diff_app
    else
      # Diff mode only implements plain/json/yaml/toml. Any other explicit
      # format (only-url, curl, sarif, oas3, …) was silently rendered as the
      # decorated text diff, corrupting automation pipelines that expected the
      # requested format.
      fmt = options["format"].to_s
      unless fmt.empty? || fmt == "plain"
        # Straight to STDERR rather than through `@logger.warning`, which
        # `--no-log` silences wholesale — and `--no-log` is exactly the run
        # that needs to hear this. `noir scan new --diff-path old -f sarif
        # --no-log -o report.sarif` in CI otherwise writes the text diff
        # into a `.sarif` file with nothing on either stream saying the
        # format request was dropped. A "your flag was ignored" notice about
        # the result stream itself belongs with the `--concurrency` clamp
        # and the other always-visible CliValidation warnings, not with the
        # progress log.
        STDERR.puts "WARNING: diff mode does not support -f #{fmt}; showing the text diff instead. Supported diff formats: plain, json, yaml, toml.".colorize(:yellow)
      end
      builder.print @endpoints, diff_app
    end
  end

  # Renders the report in the requested format. Which builder that is, and
  # which formats exist at all, is the annotated-builder catalog's business
  # (`Noir::OutputFormats`) — this used to be a 70-line `case` that was the
  # fourth place a format had to be listed.
  def report
    format = options["format"].to_s
    return if Noir::OutputFormats.render(format, @options, @endpoints, @passive_results, analyzer_failures)

    # `CliValidation` rejects an unknown `-f` before a scan starts, so this
    # only catches a library caller that built the options hash itself:
    # fall back to the default format rather than printing nothing at all.
    Noir::OutputFormats.render(Noir::OutputFormats::DEFAULT, @options, @endpoints, @passive_results, analyzer_failures)
  end

  def techs=(value : Array(String))
    @techs = value
  end
end
