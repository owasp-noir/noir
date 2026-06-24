require "./logger"
require "./endpoint"
require "../utils/*"
require "colorize"

class OutputBuilder
  @@prepared_output_files = Set(String).new

  @logger : NoirLogger
  @options : Hash(String, YAML::Any)
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @output_file : String

  property io : IO

  def initialize(options : Hash(String, YAML::Any))
    @is_debug = any_to_bool(options["debug"])
    @is_verbose = any_to_bool(options["verbose"])
    @options = options
    # Auto-disable color when STDOUT isn't a terminal — the `only-url`,
    # `only-param`, `only-header`, `only-cookie`, and `only-tag`
    # formats use `.colorize(...).toggle(@is_color)`, which (unlike a
    # bare `.colorize`) bypasses Crystal's TTY auto-detect and emits
    # ANSI codes even into pipes. `noir -f only-url | sort -u` ended up
    # with `\e[93m/sign\e[39m` in the pipe, breaking the downstream
    # tools these formats exist to feed.
    # `--no-color` / `NO_COLOR` (handled at the router) still take
    # precedence; this only flips off the default-on behavior when
    # stdout is redirected.
    @is_color = any_to_bool(options["color"]) && STDOUT.tty?
    @is_log = any_to_bool(options["nolog"])
    @output_file = options["output"].to_s
    @io = STDOUT

    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log
  end

  def ob_puts(message)
    @io.puts message
    unless @output_file.empty?
      begin
        File.open(@output_file, output_file_mode) do |file|
          file.puts message
        end
      rescue e : File::Error
        STDERR.puts "ERROR: Could not write output file '#{@output_file}': #{e.message}".colorize(:yellow)
        exit(1)
      end
    end
  end

  private def output_file_mode : String
    return "a" if @@prepared_output_files.includes?(@output_file)

    @@prepared_output_files << @output_file
    "w"
  end

  def print
    # After inheriting the class, write an action code here.
  end

  def bake_endpoint(url : String, params : Array(Param))
    @logger.debug "Baking endpoint #{url} with #{params.size} params."

    final_url = url
    final_body = ""
    final_path_params = [] of String
    final_headers = [] of String
    final_cookies = [] of String
    final_tags = [] of String
    is_json = false
    first_query = true
    first_form = true

    if final_url.starts_with?("//")
      if final_url.size != 2 && final_url[2] != ':'
        final_url = final_url[1..]
      end
    end

    unless params.nil?
      params.each do |param|
        if param.param_type == "query"
          if first_query
            final_url += "?#{param.name}=#{param.value}"
            first_query = false
          else
            final_url += "&#{param.name}=#{param.value}"
          end
        end

        if param.param_type == "form"
          if first_form
            final_body += "#{param.name}=#{param.value}"
            first_form = false
          else
            final_body += "&#{param.name}=#{param.value}"
          end
        end

        if param.param_type == "path"
          final_path_params << "#{param.name}"
        end

        if param.param_type == "header"
          final_headers << "#{param.name}: #{param.value}"
        end

        if param.param_type == "cookie"
          final_cookies << "#{param.name}=#{param.value}"
        end

        if param.param_type == "json"
          is_json = true
        end

        unless param.tags.empty?
          param.tags.each do |tag|
            final_tags << tag.name
          end
        end
      end

      if is_json
        json_tmp = Hash(String, String).new

        params.each do |param|
          if param.param_type == "json"
            json_tmp[param.name] = param.value
          end
        end

        final_body = json_tmp.to_json
      end
    end

    @logger.debug "Baked endpoints"
    @logger.debug " + Final URL: #{final_url}"
    @logger.debug " + Path Params: #{final_path_params}"
    @logger.debug " + Body: #{final_body}"
    @logger.debug " + Headers: #{final_headers}"
    @logger.debug " + Cookies: #{final_cookies}"
    @logger.debug " + Tags: #{final_tags}"

    {
      url:        final_url,
      body:       final_body,
      path_param: final_path_params,
      header:     final_headers,
      cookie:     final_cookies,
      tags:       final_tags.uniq,
      body_type:  is_json ? "json" : "form",
    }
  end

  protected def noir_callee_json(callee : Callee) : JSON::Any
    data = {
      "name" => JSON::Any.new(callee.name),
    } of String => JSON::Any

    if path = callee.path
      data["path"] = JSON::Any.new(path)
    end

    if line = callee.line
      data["line"] = JSON::Any.new(line.to_i64)
    end

    JSON::Any.new(data)
  end

  protected def noir_callees_json(endpoint : Endpoint) : Array(JSON::Any)
    endpoint.callees.map { |callee| noir_callee_json(callee) }
  end

  protected def add_noir_callees_extension(operation : Hash(String, JSON::Any), endpoint : Endpoint)
    return if endpoint.callees.empty?

    operation["x-noir-callees"] = JSON::Any.new(noir_callees_json(endpoint))
  end

  protected def noir_ai_context_entry_json(entry : AIContextEntry) : JSON::Any
    data = {
      "kind" => JSON::Any.new(entry.kind),
      "name" => JSON::Any.new(entry.name),
    } of String => JSON::Any

    if source = entry.source
      data["source"] = JSON::Any.new(source)
    end

    if description = entry.description
      data["description"] = JSON::Any.new(description)
    end

    if path = entry.path
      data["path"] = JSON::Any.new(path)
    end

    if line = entry.line
      data["line"] = JSON::Any.new(line.to_i64)
    end

    if confidence = entry.confidence
      data["confidence"] = JSON::Any.new(confidence.to_i64)
    end

    if snippet = entry.snippet
      data["snippet"] = JSON::Any.new(snippet)
    end

    JSON::Any.new(data)
  end

  protected def noir_ai_context_json(endpoint : Endpoint) : JSON::Any?
    context = endpoint.ai_context
    return unless context
    return if context.empty?

    JSON::Any.new({
      "guards"     => JSON::Any.new(context.guards.map { |entry| noir_ai_context_entry_json(entry) }),
      "callees"    => JSON::Any.new(context.callees.map { |entry| noir_ai_context_entry_json(entry) }),
      "sources"    => JSON::Any.new(context.sources.map { |entry| noir_ai_context_entry_json(entry) }),
      "sinks"      => JSON::Any.new(context.sinks.map { |entry| noir_ai_context_entry_json(entry) }),
      "validators" => JSON::Any.new(context.validators.map { |entry| noir_ai_context_entry_json(entry) }),
      "signals"    => JSON::Any.new(context.signals.map { |entry| noir_ai_context_entry_json(entry) }),
    } of String => JSON::Any)
  end

  protected def add_noir_ai_context_extension(operation : Hash(String, JSON::Any), endpoint : Endpoint)
    context_json = noir_ai_context_json(endpoint)
    if context_json
      operation["x-noir-ai-context"] = context_json
    end
  end

  protected def noir_callees_description(endpoint : Endpoint) : String?
    return if endpoint.callees.empty?

    lines = ["Noir callees:"]
    endpoint.callees.each do |callee|
      lines << "- #{format_noir_callee(callee)}"
    end
    lines.join("\n")
  end

  protected def noir_ai_context_description(endpoint : Endpoint) : String?
    context = endpoint.ai_context
    return unless context
    return if context.empty?

    lines = ["Noir AI context:"]
    append_ai_context_description(lines, "guards", context.guards)
    append_ai_context_description(lines, "callees", context.callees)
    append_ai_context_description(lines, "sources", context.sources)
    append_ai_context_description(lines, "sinks", context.sinks)
    append_ai_context_description(lines, "validators", context.validators)
    append_ai_context_description(lines, "signals", context.signals)
    lines.join("\n")
  end

  private def format_noir_callee(callee : Callee) : String
    if path = callee.path
      if line = callee.line
        return "#{callee.name} (#{path}:#{line})"
      end

      return "#{callee.name} (#{path})"
    end

    if line = callee.line
      return "#{callee.name} (line #{line})"
    end

    callee.name
  end

  private def format_ai_context_entry(entry : AIContextEntry) : String
    label = "#{entry.kind}: #{entry.name}"
    label += " (#{entry.path}:#{entry.line})" if entry.path && entry.line
    label += " (#{entry.path})" if entry.path && entry.line.nil?
    label += " (line #{entry.line})" if entry.path.nil? && entry.line
    label += " [#{entry.source}]" if entry.source
    label += " - #{entry.description}" if entry.description
    label += " :: #{entry.snippet}" if entry.snippet
    label
  end

  private def append_ai_context_description(lines : Array(String), label : String, entries : Array(AIContextEntry))
    return if entries.empty?

    lines << "- #{label}:"
    entries.each do |entry|
      lines << "  - #{format_ai_context_entry(entry)}"
    end
  end

  getter logger, output_file
end
