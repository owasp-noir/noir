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
      update_status_codes
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

  def update_status_codes
    @logger.sub "➔ Updating status codes."
    final = [] of Endpoint

    exclude_codes = [] of Int32
    unless @options["exclude_codes"].to_s.empty?
      @options["exclude_codes"].to_s.split(",").each do |code|
        exclude_codes << code.strip.to_i
      end
    end

    @endpoints.each do |endpoint|
      request_method = requestable_http_methods(endpoint.method).first?
      unless request_method
        final << endpoint
        next
      end

      begin
        if endpoint.params.empty?
          response = perform_request(
            get_symbol(request_method),
            endpoint.url
          )
          endpoint.details.status_code = response.status_code
          unless exclude_codes.includes?(response.status_code)
            final << endpoint
          end
        else
          endpoint_hash = endpoint.params_to_hash
          is_json = false
          body = if endpoint_hash["json"].empty?
                   endpoint_hash["form"]
                 else
                   is_json = true
                   endpoint_hash["json"]
                 end

          response = perform_request(
            get_symbol(request_method),
            endpoint.url,
            endpoint_hash["query"],
            body,
            is_json
          )
          endpoint.details.status_code = response.status_code
          unless exclude_codes.includes?(response.status_code)
            final << endpoint
          end
        end
      rescue e
        @logger.error "Failed to get status code for #{endpoint.url} (#{e.message})."
        final << endpoint
      end
    end

    @endpoints = final
  end

  def perform_request(method, url, params = {} of String => String, form = {} of String => String, json = false)
    Crest::Request.execute(
      method: method,
      url: url,
      tls: OpenSSL::SSL::Context::Client.insecure,
      user_agent: "Noir/#{Noir::VERSION}",
      params: params,
      form: form,
      json: json,
      handle_errors: false,
      read_timeout: 5.second
    )
  end

  # Backward compatibility wrapper methods for tests
  def optimize_endpoints
    optimizer = LLMEndpointOptimizer.new(@logger, @options)
    @endpoints = optimizer.optimize_endpoints(@endpoints)
  end

  def combine_url_and_endpoints
    optimizer = LLMEndpointOptimizer.new(@logger, @options)
    @endpoints = optimizer.combine_url_and_endpoints(@endpoints)
  end

  def add_path_parameters
    optimizer = LLMEndpointOptimizer.new(@logger, @options)
    @endpoints = optimizer.add_path_parameters(@endpoints)
  end

  def apply_pvalue(param_type, param_name, param_value) : String
    optimizer = LLMEndpointOptimizer.new(@logger, @options)
    optimizer.apply_pvalue(param_type, param_name, param_value)
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
      # Print diff output
      builder.print @endpoints, diff_app
    end
  end

  def report
    case options["format"]
    when "yaml"
      builder = OutputBuilderYaml.new @options
      builder.print @endpoints, @passive_results
    when "json"
      builder = OutputBuilderJson.new @options
      builder.print @endpoints, @passive_results
    when "jsonl"
      builder = OutputBuilderJsonl.new @options
      builder.print @endpoints
    when "toml"
      builder = OutputBuilderToml.new @options
      builder.print @endpoints, @passive_results
    when "markdown-table"
      builder = OutputBuilderMarkdownTable.new @options
      builder.print @endpoints
    when "httpie"
      builder = OutputBuilderHttpie.new @options
      builder.print @endpoints
    when "curl"
      builder = OutputBuilderCurl.new @options
      builder.print @endpoints
    when "powershell"
      builder = OutputBuilderPowershell.new @options
      builder.print @endpoints
    when "adb"
      builder = OutputBuilderAdb.new @options
      builder.print @endpoints
    when "simctl"
      builder = OutputBuilderSimctl.new @options
      builder.print @endpoints
    when "sarif"
      builder = OutputBuilderSarif.new @options
      builder.print @endpoints, @passive_results
    when "oas2"
      builder = OutputBuilderOas2.new @options
      builder.print @endpoints
    when "oas3"
      builder = OutputBuilderOas3.new @options
      builder.print @endpoints
    when "postman"
      builder = OutputBuilderPostman.new @options
      builder.print @endpoints
    when "only-url"
      builder = OutputBuilderOnlyUrl.new @options
      builder.print @endpoints
    when "only-param"
      builder = OutputBuilderOnlyParam.new @options
      builder.print @endpoints
    when "only-header"
      builder = OutputBuilderOnlyHeader.new @options
      builder.print @endpoints
    when "only-cookie"
      builder = OutputBuilderOnlyCookie.new @options
      builder.print @endpoints
    when "only-tag"
      builder = OutputBuilderOnlyTag.new @options
      builder.print @endpoints
    when "mermaid"
      builder = OutputBuilderMermaid.new @options
      builder.print @endpoints, @passive_results
    when "html"
      builder = OutputBuilderHtml.new @options
      builder.print @endpoints, @passive_results
    else
      builder = OutputBuilderCommon.new @options

      @logger.heading "Endpoint Results:"
      builder.print @endpoints

      print_passive_results
    end
  end

  def print_passive_results
    unless @passive_results.empty?
      @logger.puts ""
      @logger.heading "Passive Results:"
      builder = OutputBuilderPassiveScan.new @options
      builder.print @passive_results, @logger, @is_color
    end
  end

  def techs=(value : Array(String))
    @techs = value
  end
end
