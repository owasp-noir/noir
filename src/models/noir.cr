require "../detector/detector.cr"
require "../analyzer/analyzer.cr"
require "../tagger/tagger.cr"
require "../passive_scan/rules.cr"
require "../deliver/*"
require "../output_builder/*"
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
      if @options["passive_scan_path"].as_a.size > 0
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
    detected_techs = detect_techs options["base"].to_s, options, @passive_scans, @logger
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
    optimize_endpoints
    combine_url_and_endpoints
    add_path_parameters

    # Set status code
    if any_to_bool(@options["status_codes"]) == true || @options["exclude_codes"].to_s != ""
      update_status_codes
    end

    # Run tagger
    if any_to_bool(@options["all_taggers"]) == true
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

  def optimize_endpoints
    @logger.info "Optimizing endpoints."
    @logger.sub "➔ Removing duplicated endpoints and params."
    final = [] of Endpoint
    duplicate_count = 0
    allowed_methods = get_allowed_methods

    @endpoints.each do |endpoint|
      tiny_tmp = endpoint

      # Check if method is allowed, otherwise default to GET
      if !allowed_methods.includes?(tiny_tmp.method.upcase)
        @logger.debug_sub "  - Invalid HTTP method: '#{tiny_tmp.method}' for '#{tiny_tmp.url}', defaulting to GET"
        tiny_tmp.method = "GET"
      end

      # Remove space in param name
      if endpoint.params.size > 0
        tiny_tmp.params = [] of Param
        endpoint.params.each do |param|
          if !param.name.includes? " "
            param.value = apply_pvalue(param.param_type, param.name, param.value).to_s
            tiny_tmp.params << param
          end
        end
      end

      # Duplicate check
      if tiny_tmp.url != ""
        # Check start with slash
        if tiny_tmp.url[0] != "/"
          tiny_tmp.url = "/#{tiny_tmp.url}"
        end

        # Check double slash
        tiny_tmp.url = tiny_tmp.url.gsub_repeatedly("//", "/")

        is_new = true
        final.each do |dup|
          if dup.method == tiny_tmp.method && dup.url == tiny_tmp.url
            @logger.debug_sub "  - Found duplicated endpoint: #{tiny_tmp.method} #{tiny_tmp.url}"
            is_new = false
            duplicate_count += 1
            tiny_tmp.params.each do |param|
              existing_param = dup.params.find { |dup_param| dup_param.name == param.name }
              unless existing_param
                dup.params << param
              end
            end
          end
        end
        if is_new || final.size == 0
          final << tiny_tmp
        end
      end
    end

    @endpoints = final
    @logger.verbose_sub "➔ Total duplicated endpoints: #{duplicate_count}"
  end

  def apply_pvalue(param_type, param_name, param_value) : String
    case param_type
    when "query"
      pvalue_target = @options["set_pvalue_query"]
    when "json"
      pvalue_target = @options["set_pvalue_json"]
    when "form"
      pvalue_target = @options["set_pvalue_form"]
    when "header"
      pvalue_target = @options["set_pvalue_header"]
    when "cookie"
      pvalue_target = @options["set_pvalue_cookie"]
    when "path"
      pvalue_target = @options["set_pvalue_path"]
    else
      pvalue_target = YAML::Any.new([] of YAML::Any)
    end

    # Merge with @options["set_pvalue"]
    merged_pvalue_target = [] of YAML::Any
    merged_pvalue_target.concat(pvalue_target.as_a)
    merged_pvalue_target.concat(@options["set_pvalue"].as_a)

    merged_pvalue_target.each do |pvalue|
      pvalue_str = pvalue.to_s
      if pvalue_str.includes?("=") || pvalue_str.includes?(":")
        first_equal = pvalue_str.index("=")
        first_colon = pvalue_str.index(":")

        if first_equal && (!first_colon || first_equal < first_colon)
          splited = pvalue_str.split("=", 2)
          if splited[0] == param_name || splited[0] == "*"
            return splited[1].to_s
          end
        elsif first_colon
          splited = pvalue_str.split(":", 2)
          if splited[0] == param_name || splited[0] == "*"
            return splited[1].to_s
          end
        end
      else
        return pvalue_str
      end
    end

    param_value.to_s
  end

  def combine_url_and_endpoints
    tmp = [] of Endpoint
    target_url = @options["url"].to_s

    if target_url != ""
      @logger.sub "➔ Combining url and endpoints."
      @logger.debug_sub " + Before size: #{@endpoints.size}"

      @endpoints.each do |endpoint|
        tmp_endpoint = endpoint
        if tmp_endpoint.url.includes? target_url
          tmp_endpoint.url = tmp_endpoint.url.gsub(target_url, "")
        end

        tmp_endpoint.url = tmp_endpoint.url.gsub_repeatedly("//", "/")
        if tmp_endpoint.url != ""
          if target_url[-1] == '/' && tmp_endpoint.url[0] == '/'
            tmp_endpoint.url = tmp_endpoint.url[1..]
          elsif target_url[-1] != '/' && tmp_endpoint.url[0] != '/'
            tmp_endpoint.url = "/#{tmp_endpoint.url}"
          end
        end

        tmp_endpoint.url = target_url + tmp_endpoint.url
        tmp << tmp_endpoint
      end

      @logger.debug_sub " + After size: #{tmp.size}"
      @endpoints = tmp
    end
  end

  def add_path_parameters
    @logger.sub "➔ Adding path parameters by URL."
    final = [] of Endpoint

    @endpoints.each do |endpoint|
      new_endpoint = endpoint

      scans = endpoint.url.scan(/\/\{([^}]+)\}/).flatten
      scans.each do |match|
        param = match[1].split(":")[0]
        new_value = apply_pvalue("path", param, "")
        if new_value != ""
          new_endpoint.url = new_endpoint.url.gsub("{#{match[1]}}", new_value)
        end

        new_param = Param.new(param, "", "path")
        unless new_endpoint.params.includes?(new_param)
          new_endpoint.params << new_param
        end
      end

      scans = endpoint.url.scan(/\/:([^\/]+)/).flatten
      scans.each do |match|
        new_value = apply_pvalue("path", match[1], "")
        if new_value != ""
          new_endpoint.url = new_endpoint.url.gsub(":#{match[1]}", new_value)
        end

        new_param = Param.new(match[1], "", "path")
        unless new_endpoint.params.includes?(new_param)
          new_endpoint.params << new_param
        end
      end

      scans = endpoint.url.scan(/<([^>]+)>/).flatten
      scans.each do |match|
        parts = match[1].split(":")
        if parts.size > 1
          # Handle both Django style <type:name> and Marten style <name:type>
          # Check if first part looks like a type (int, str, slug, uuid, etc.)
          if parts[0] =~ /^(int|str|string|slug|uuid|float|bool|path)$/
            # Django style: <type:name>
            param = parts[1]
          else
            # Marten style: <name:type> 
            param = parts[0]
          end
        else
          param = parts[0]
        end
        
        new_value = apply_pvalue("path", param, "")
        if new_value != ""
          new_endpoint.url = new_endpoint.url.gsub("<#{match[1]}>", new_value)
        end

        new_param = Param.new(param, "", "path")
        unless new_endpoint.params.includes?(new_param)
          new_endpoint.params << new_param
        end
      end

      final << new_endpoint
    end

    @endpoints = final
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
        if endpoint.params.size > 0
          endpoint_hash = endpoint.params_to_hash
          body = {} of String => String
          is_json = false
          if endpoint_hash["json"].size > 0
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
    when "markdown-table"
      builder = OutputBuilderMarkdownTable.new @options
      builder.print @endpoints
    when "httpie"
      builder = OutputBuilderHttpie.new @options
      builder.print @endpoints
    when "curl"
      builder = OutputBuilderCurl.new @options
      builder.print @endpoints
    when "oas2"
      buidler = OutputBuilderOas2.new @options
      buidler.print @endpoints
    when "oas3"
      buidler = OutputBuilderOas3.new @options
      buidler.print @endpoints
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
    else
      builder = OutputBuilderCommon.new @options

      @logger.heading "Endpoint Results:"
      builder.print @endpoints

      print_passive_results
    end
  end

  def print_passive_results
    if @passive_results.size > 0
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
