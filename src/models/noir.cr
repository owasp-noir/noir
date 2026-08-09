require "../detector/detector.cr"
require "../analyzer/analyzer.cr"
require "../tagger/tagger.cr"
require "../passive_scan/rules.cr"
require "../deliver/*"
require "../output_builder/*"
require "../optimizer/llm_optimizer.cr"
require "../ai_context/augmentor.cr"
require "../mobile/linker.cr"
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
  @noir_home : String
  @passive_scans : Array(PassiveScan)
  @passive_results : Array(PassiveScanResult)

  getter options, techs, endpoints, logger, passive_results

  def initialize(options)
    @options = options
    @config_file = @options["config_file"].to_s
    @noir_home = get_home
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

    if ai_context_enabled?
      @options["include_callee"] = YAML::Any.new(true)
    end

    if any_to_bool(@options["passive_scan"])
      @logger.info "Passive scanner enabled."

      # Check for passive rules updates unless disabled
      unless any_to_bool(@options["passive_scan_no_update_check"])
        # Initialize rules if they don't exist
        PassiveRulesUpdater.initialize_rules(@logger)

        # Check for updates (auto-update if enabled)
        auto_update = any_to_bool(@options["passive_scan_auto_update"])
        PassiveRulesUpdater.check_for_updates(@logger, auto_update)
      end

      if !@options["passive_scan_path"].as_a.empty?
        @logger.sub "├── Using custom passive rules only (bundled rules skipped)."
        # Concatenate rules from every passive_scan_path. The previous
        # assignment (`@passive_scans = NoirPassiveScan.load_rules …`)
        # inside the loop silently dropped every path except the last
        # one whenever the user passed multiple --passive-scan-path
        # entries.
        @options["passive_scan_path"].as_a.each do |rule_path|
          @passive_scans.concat(NoirPassiveScan.load_rules(rule_path.to_s, @logger))
        end
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

  def run
    puts @techs
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
    @endpoints = analysis_endpoints options, @techs, @logger

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
          @logger.debug "Tagger: #{tagger}"
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
      # requested format. Warn (to STDERR) so the mismatch is visible.
      fmt = options["format"].to_s
      unless fmt.empty? || fmt == "plain"
        @logger.warning "Diff mode does not support -f #{fmt}; showing the text diff instead. Supported diff formats: plain, json, yaml, toml."
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
    return if Noir::OutputFormats.render(format, @options, @endpoints, @passive_results)

    # `CliValidation` rejects an unknown `-f` before a scan starts, so this
    # only catches a library caller that built the options hash itself:
    # fall back to the default format rather than printing nothing at all.
    Noir::OutputFormats.render(Noir::OutputFormats::DEFAULT, @options, @endpoints, @passive_results)
  end

  def techs=(value : Array(String))
    @techs = value
  end
end
