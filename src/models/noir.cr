require "../detector/detector.cr"
require "../analyzer/analyzer.cr"
require "../tagger/tagger.cr"
require "../deliver/*"
require "../output_builder/*"
require "./endpoint.cr"
require "./logger.cr"
require "../utils/string_extension.cr"
require "json"
require "yaml"

class NoirRunner
  @options : Hash(String, YAML::Any)
  @techs : Array(String)
  @endpoints : Array(Endpoint)
  @logger : NoirLogger
  @send_proxy : String
  @send_req : String
  @send_es : String
  @is_debug : Bool
  @is_color : Bool
  @is_log : Bool
  @concurrency : Int32
  @config_file : String

  macro define_getter_methods(names)
    {% for name, index in names %}
      def {{name.id}}
        @{{name.id}}
      end
    {% end %}
  end

  define_getter_methods [options, techs, endpoints, logger]

  def initialize(options)
    @options = options
    @config_file = @options["config_file"].to_s

    if @config_file != ""
      config = YAML.parse(File.read(@config_file)).as_h
      symbolized_hash = config.transform_keys(&.to_s)
      @options = @options.merge(symbolized_hash) { |_, _, new_val| new_val }
    end

    @techs = [] of String
    @endpoints = [] of Endpoint
    @send_proxy = @options["send_proxy"].to_s
    @send_req = @options["send_req"].to_s
    @send_es = @options["send_es"].to_s
    @is_debug = str_to_bool(@options["debug"])
    @is_color = str_to_bool(@options["color"])
    @is_log = str_to_bool(@options["nolog"])
    @concurrency = @options["concurrency"].to_s.to_i

    @logger = NoirLogger.new @is_debug, @is_color, @is_log

    if @options["techs"].to_s.size > 0
      techs_tmp = @options["techs"].to_s.split(",")
      @logger.success "Setting #{techs_tmp.size} techs from command line."
      techs_tmp.each do |tech|
        @techs << NoirTechs.similar_to_tech(tech)
        @logger.debug "Added #{tech} to techs."
      end
    end
  end

  def run
    puts @techs
  end

  def detect
    detected_techs = detect_techs options["base"].to_s, options, @logger
    @techs += detected_techs
    if @is_debug
      @logger.debug("CodeLocator Table:")
      locator = CodeLocator.instance
      locator.show_table
    end
  end

  def analyze
    @endpoints = analysis_endpoints options, @techs, @logger
    optimize_endpoints
    combine_url_and_endpoints
    add_path_parameters

    # Run tagger
    if @options["all_taggers"] == true
      @logger.success "Running all taggers."
      NoirTaggers.run_tagger @endpoints, @options, "all"
      if @is_debug
        NoirTaggers.get_taggers.each do |tagger|
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
    final = [] of Endpoint

    @endpoints.each do |endpoint|
      tiny_tmp = endpoint
      if endpoint.params.size > 0
        tiny_tmp.params = [] of Param
        endpoint.params.each do |param|
          if !param.name.includes? " "
            param.value = apply_pvalue(param.param_type, param.name, param.value).to_s
            tiny_tmp.params << param
          end
        end
      end

      if tiny_tmp.url != ""
        is_new = true
        final.each do |dup|
          if dup.method == tiny_tmp.method && dup.url == tiny_tmp.url
            is_new = false
            tiny_tmp.params.each do |param|
              existing_param = dup.params.find { |p| p.name == param.name }
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
      if pvalue.to_s.includes? "="
        splited = pvalue.to_s.split("=")
        if splited[0] == param_name
          return splited[1].to_s
        end
      elsif pvalue.to_s.includes? ":"
        splited = pvalue.to_s.split(":")
        if splited[0] == param_name
          return splited[1].to_s
        end
      else
        return pvalue.to_s
      end
    end

    param_value.to_s
  end

  def combine_url_and_endpoints
    tmp = [] of Endpoint
    target_url = @options["url"].to_s

    if target_url != ""
      @logger.info "Combining url and endpoints."
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

      @endpoints = tmp
    end
  end

  def add_path_parameters
    @logger.info "Adding path parameters by URL"
    final = [] of Endpoint

    @endpoints.each do |endpoint|
      new_endpoint = endpoint

      scans = endpoint.url.scan(/\/\{([^}]+)\}/).flatten
      scans.each do |match|
        param = match[1].split(":")[-1]
        new_value = apply_pvalue("path", param, "")
        if new_value != ""
          new_endpoint.url = new_endpoint.url.gsub("{#{param}}", new_value)
        end

        new_endpoint.params << Param.new(param, "", "path")
      end

      scans = endpoint.url.scan(/\/:([^\/]+)/).flatten
      scans.each do |match|
        param = match[1].split(":")[-1]
        new_value = apply_pvalue("path", param, "")
        if new_value != ""
          new_endpoint.url = new_endpoint.url.gsub(":#{match[1]}", new_value)
        end

        new_endpoint.params << Param.new(param, "", "path")
      end

      scans = endpoint.url.scan(/\/<([^>]+)>/).flatten
      scans.each do |match|
        param = match[1].split(":")[-1]
        new_value = apply_pvalue("path", param, "")
        if new_value != ""
          new_endpoint.url = new_endpoint.url.gsub("<#{match[1]}>", new_value)
        end
        new_endpoint.params << Param.new(param, "", "path")
      end

      final << new_endpoint
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
      puts @endpoints.to_yaml
    when "json"
      puts @endpoints.to_json
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
    else
      builder = OutputBuilderCommon.new @options
      builder.print @endpoints
    end
  end
end
