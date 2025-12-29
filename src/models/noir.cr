require "../detector/detector.cr"
require "../analyzer/analyzer.cr"
require "../tagger/tagger.cr"
require "../passive_scan/rules.cr"
require "../deliver/*"
require "../output_builder/*"
require "../optimizer/llm_optimizer.cr"
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
  @send_proxy : String
  @send_req : Bool
  @send_es : String
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @concurrency : Int32
  @config_file : String
  @noir_home : String
  @passive_scans : Array(PassiveScan)
  @passive_results : Array(PassiveScanResult)

  macro define_getter_methods(names)
    {% for name, index in names %}
      def {{name.id}}
        @{{name.id}}
      end
    {% end %}
  end

  define_getter_methods [options, techs, endpoints, logger, passive_results]

  def initialize(options)
    @options = options
    @config_file = @options["config_file"].to_s
    @noir_home = get_home
    @passive_scans = [] of PassiveScan
    @passive_results = [] of PassiveScanResult

    if @config_file != ""
      config = YAML.parse(File.read(@config_file)).as_h
      symbolized_hash = config.transform_keys(&.to_s)
      @options = @options.merge(symbolized_hash) { |_, _, new_val| new_val }
    end

    @techs = [] of String
    @endpoints = [] of Endpoint
    @send_proxy = @options["send_proxy"].to_s
    @send_req = any_to_bool(@options["send_req"])
    @send_es = @options["send_es"].to_s
    @is_debug = any_to_bool(@options["debug"])
    @is_verbose = any_to_bool(@options["verbose"])
    @is_color = any_to_bool(@options["color"])
    @is_log = any_to_bool(@options["nolog"])
    @concurrency = @options["concurrency"].to_s.to_i

    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log

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
        @logger.sub "├── Using custom passive rules."
        @options["passive_scan_path"].as_a.each do |rule_path|
          @passive_scans = NoirPassiveScan.load_rules rule_path.to_s, @logger
        end
      else
        @logger.sub "├── Using default passive rules."
        @passive_scans = NoirPassiveScan.load_rules "#{@noir_home}/passive_rules/", @logger
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

    # Set status code
    if any_to_bool(@options["status_codes"]) || @options["exclude_codes"].to_s != ""
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
    elsif @options["use_taggers"] != ""
      @logger.success "Running #{@options["use_taggers"]} taggers."
      NoirTaggers.run_tagger @endpoints, @options, @options["use_taggers"].to_s
    end

    # Run deliver
    deliver
  end

  def update_status_codes
    @logger.sub "➔ Updating status codes."
    final = [] of Endpoint

    exclude_codes = [] of Int32
    if @options["exclude_codes"].to_s != ""
      @options["exclude_codes"].to_s.split(",").each do |code|
        exclude_codes << code.strip.to_i
      end
    end

    @endpoints.each do |endpoint|
      begin
        if !endpoint.params.empty?
          endpoint_hash = endpoint.params_to_hash
          body = {} of String => String
          is_json = false
          if !endpoint_hash["json"].empty?
            is_json = true
            body = endpoint_hash["json"]
          else
            body = endpoint_hash["form"]
          end

          response = Crest::Request.execute(
            method: get_symbol(endpoint.method),
            url: endpoint.url,
            tls: OpenSSL::SSL::Context::Client.insecure,
            user_agent: "Noir/#{Noir::VERSION}",
            params: endpoint_hash["query"],
            form: body,
            json: is_json,
            handle_errors: false,
            read_timeout: 5.second
          )
          endpoint.details.status_code = response.status_code
          unless exclude_codes.includes?(response.status_code)
            final << endpoint
          end
        else
          response = Crest::Request.execute(
            method: get_symbol(endpoint.method),
            url: endpoint.url,
            tls: OpenSSL::SSL::Context::Client.insecure,
            user_agent: "Noir/#{Noir::VERSION}",
            handle_errors: false,
            read_timeout: 5.second
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
    if @send_proxy != ""
      @logger.info "Sending requests with proxy #{@send_proxy}."
      deliver = SendWithProxy.new(@options)
      deliver.run(@endpoints)
    end

    if @send_req != false
      @logger.info "Sending requests without proxy."
      deliver = SendReq.new(@options)
      deliver.run(@endpoints)
    end

    if @send_es != ""
      @logger.info "Sending requests to Elasticsearch."
      deliver = SendElasticSearch.new(@options)
      deliver.run(@endpoints, @send_es)
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
    when "sarif"
      builder = OutputBuilderSarif.new @options
      builder.print @endpoints, @passive_results
    when "oas2"
      buidler = OutputBuilderOas2.new @options
      buidler.print @endpoints
    when "oas3"
      buidler = OutputBuilderOas3.new @options
      buidler.print @endpoints
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
    if !@passive_results.empty?
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
