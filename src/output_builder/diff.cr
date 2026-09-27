require "../models/output_builder"
require "../models/endpoint"
require "./toml_serializer"
require "./markdown_cell"
require "sarif"

require "json"
require "yaml"
require "colorize"

class OutputBuilderDiff < OutputBuilder
  include OutputBuilderTomlSerializer
  include OutputBuilderMarkdownCell

  AUTH_TAG = "auth"

  # A param named by what a client has to send: its name and where it goes.
  # The value is left out on purpose — it is an example or default read out
  # of the code, and a new default is not new attack surface.
  struct ParamRef
    include JSON::Serializable
    include YAML::Serializable

    getter name : String
    getter param_type : String

    def initialize(@name : String, @param_type : String)
    end
  end

  # Why a route present on both sides is reported as changed. `changed`
  # carries the endpoint as it is now; this says what is different about it,
  # so a reviewer does not have to diff two endpoint objects by eye.
  struct Change
    include JSON::Serializable
    include YAML::Serializable

    getter method : String
    getter url : String
    getter params_added : Array(ParamRef)
    getter params_removed : Array(ParamRef)
    getter tags_added : Array(String)
    getter tags_removed : Array(String)
    # The route carried an `auth` tag before and does not now: the
    # security-relevant reading of a tag change, spelled out so a CI gate
    # does not have to know which tag name the auth taggers use.
    getter? auth_removed : Bool

    def initialize(@method : String, @url : String, @params_added : Array(ParamRef),
                   @params_removed : Array(ParamRef), @tags_added : Array(String),
                   @tags_removed : Array(String))
      @auth_removed = @tags_removed.includes?(AUTH_TAG)
    end

    def empty? : Bool
      params_added.empty? && params_removed.empty? && tags_added.empty? && tags_removed.empty?
    end
  end

  alias Result = NamedTuple(added: Array(Endpoint), removed: Array(Endpoint), changed: Array(Endpoint), changes: Array(Change))

  def diff(new_endpoints : Array(Endpoint), old_endpoints : Array(Endpoint)) : Result
    added = [] of Endpoint
    changed = [] of Endpoint
    removed = [] of Endpoint
    changes = [] of Change

    # Indexed by (url, method) instead of a `find` per endpoint, which made
    # the diff quadratic — a monorepo with a few thousand endpoints on each
    # side spent longer here than in either scan. `put_if_absent` keeps the
    # first endpoint for a key, the one `find` used to return.
    old_index = index_by_route(old_endpoints)
    new_index = index_by_route(new_endpoints)

    new_endpoints.each do |new_endpoint|
      if matching_old_endpoint = old_index[{new_endpoint.url, new_endpoint.method}]?
        change = describe_change(new_endpoint, matching_old_endpoint)
        unless change.empty?
          changed << new_endpoint
          changes << change
        end
      else
        added << new_endpoint
      end
    end

    old_endpoints.each do |old_endpoint|
      removed << old_endpoint unless new_index.has_key?({old_endpoint.url, old_endpoint.method})
    end

    {added: added, removed: removed, changed: changed, changes: changes}
  end

  # Params are compared by name and request type (the key `push_param`
  # dedupes on, so `body` and `json` are one bucket), tags by name.
  # `Endpoint#==` used to decide this and compared param values too, so a
  # changed default reported the route as changed without anything a
  # scanner would send differently.
  def describe_change(new_endpoint : Endpoint, old_endpoint : Endpoint) : Change
    new_params = param_index(new_endpoint)
    old_params = param_index(old_endpoint)
    new_tags = new_endpoint.tags.map(&.name).uniq!.sort!
    old_tags = old_endpoint.tags.map(&.name).uniq!.sort!

    Change.new(
      method: new_endpoint.method,
      url: new_endpoint.url,
      params_added: new_params.reject { |key, _| old_params.has_key?(key) }.values,
      params_removed: old_params.reject { |key, _| new_params.has_key?(key) }.values,
      tags_added: new_tags - old_tags,
      tags_removed: old_tags - new_tags,
    )
  end

  private def param_index(endpoint : Endpoint) : Hash({String, String}, ParamRef)
    index = {} of {String, String} => ParamRef
    endpoint.params.each do |param|
      index.put_if_absent({param.name, param.request_type}) { ParamRef.new(param.name, param.param_type) }
    end
    index
  end

  private def index_by_route(endpoints : Array(Endpoint)) : Hash({String, String}, Endpoint)
    index = Hash({String, String}, Endpoint).new(initial_capacity: endpoints.size)
    endpoints.each { |endpoint| index.put_if_absent({endpoint.url, endpoint.method}, endpoint) }
    index
  end

  # How many findings each `--fail-on` category has in `result`.
  def self.gate_counts(result : Result) : Hash(String, Int32)
    {
      "added"        => result[:added].size,
      "removed"      => result[:removed].size,
      "changed"      => result[:changed].size,
      "auth-removed" => result[:changes].count(&.auth_removed?),
    }
  end

  def print(endpoints : Array(Endpoint), diff_app : NoirRunner)
    print(diff(endpoints, diff_app.endpoints))
  end

  def print(result : Result)
    common = OutputBuilderCommon.new(@options)
    common.io = io

    if result[:added].empty? && result[:removed].empty? && result[:changed].empty?
      # An empty report read as "did the diff even run?" — say it did.
      ob_puts "No endpoint was added, removed or changed."
      return
    end

    # Sections are separated by a blank line, but the first one starts the
    # report: a removed-only diff used to open with an empty line.
    separator = ""

    if !result[:added].empty?
      ob_puts "#{separator}#{format_section_header("✚", "Added", result[:added].size, :green)}"
      common.print(result[:added])
      separator = "\n"
    end

    if !result[:removed].empty?
      ob_puts "#{separator}#{format_section_header("✖", "Removed", result[:removed].size, :red)}"
      common.print(result[:removed])
      separator = "\n"
    end

    if !result[:changed].empty?
      ob_puts "#{separator}#{format_section_header("≠", "Changed", result[:changed].size, :yellow)}"
      result[:changed].zip(result[:changes]) do |endpoint, change|
        common.print([endpoint])
        ob_puts format_change(change)
      end
    end
  end

  # The `+`/`-` rows under a changed endpoint. The auth line comes first and
  # in red because it is the one a reviewer must not miss.
  private def format_change(change : Change) : String
    rows = [] of {String, Symbol}
    rows << {"! auth tag removed", :red} if change.auth_removed?
    change.params_added.each { |param| rows << {"+ #{param.param_type}: #{param.name}", :green} }
    change.params_removed.each { |param| rows << {"- #{param.param_type}: #{param.name}", :red} }
    change.tags_added.each { |tag| rows << {"+ tag: #{tag}", :green} }
    change.tags_removed.each { |tag| rows << {"- tag: #{tag}", :red} unless tag == AUTH_TAG }
    rows.join("\n") { |(text, color)| "  #{escape_control_chars(text).colorize(color).toggle(@is_color)}" }
  end

  private def format_section_header(icon : String, text : String, count : Int32, color : Symbol) : String
    title = "#{icon} #{text} (#{count})"
    line_length = 40
    padding = line_length - title.size - 2
    left_pad = (padding / 2).to_i
    right_pad = padding - left_pad

    separator = "─" * left_pad
    separator_right = "─" * right_pad

    header_line = "#{separator} #{title} #{separator_right}".colorize(color).toggle(@is_color)
    header_line.to_s
  end

  def print_json(endpoints : Array(Endpoint), diff_app : NoirRunner)
    print_json(diff(endpoints, diff_app.endpoints))
  end

  def print_json(result : Result)
    ob_puts result.to_json
  end

  def print_yaml(endpoints : Array(Endpoint), diff_app : NoirRunner)
    print_yaml(diff(endpoints, diff_app.endpoints))
  end

  def print_yaml(result : Result)
    ob_puts result.to_yaml
  end

  def print_toml(endpoints : Array(Endpoint), diff_app : NoirRunner)
    print_toml(diff(endpoints, diff_app.endpoints))
  end

  def print_toml(result : Result)
    json_str = result.to_json
    json_obj = JSON.parse(json_str)
    toml_output = generate_toml_from_diff(json_obj.as_h)
    ob_puts toml_output
  end

  private def generate_toml_from_diff(data : Hash(String, JSON::Any)) : String
    result = String.build do |io|
      data.each do |section, entries|
        if !entries.as_a.empty?
          # `changes` holds change records, not endpoints.
          item = section == "changes" ? "change" : "endpoint"
          io << "[#{section}]\n"
          entries.as_a.each do |entry|
            io << "\n[[#{section}.#{item}]]\n"
            io << generate_table_content(entry.as_h)
          end
          io << "\n"
        end
      end
    end
    result
  end

  # A pull-request comment: counts first, then the lost-auth routes, then
  # one table per section. Every cell is repo-derived text, so each goes
  # through the same escaping `-f markdown-table` uses.
  def print_markdown(result : Result)
    auth_removed = result[:changed].zip(result[:changes]).select { |(_, change)| change.auth_removed? }

    ob_puts "## Attack surface diff"
    ob_puts ""
    if result[:added].empty? && result[:removed].empty? && result[:changed].empty?
      ob_puts "No endpoint was added, removed or changed."
      return
    end

    ob_puts "| Added | Removed | Changed | Auth removed |"
    ob_puts "| ----- | ------- | ------- | ------------ |"
    ob_puts "| #{result[:added].size} | #{result[:removed].size} | #{result[:changed].size} | #{auth_removed.size} |"

    unless auth_removed.empty?
      ob_puts ""
      ob_puts "### :warning: Auth removed"
      ob_puts ""
      ob_puts "These routes had an `auth` tag before this change and do not now."
      ob_puts ""
      ob_puts "| Endpoint | Location |"
      ob_puts "| -------- | -------- |"
      auth_removed.each do |(endpoint, _)|
        ob_puts "| #{markdown_endpoint(endpoint)} | #{markdown_location(endpoint)} |"
      end
    end

    unless result[:added].empty?
      ob_puts ""
      ob_puts "### Added"
      ob_puts ""
      ob_puts "| Endpoint | Params | Location |"
      ob_puts "| -------- | ------ | -------- |"
      result[:added].each do |endpoint|
        params = endpoint.params.map { |param| ParamRef.new(param.name, param.param_type) }
        ob_puts "| #{markdown_endpoint(endpoint)} | #{markdown_params(params)} | #{markdown_location(endpoint)} |"
      end
    end

    unless result[:removed].empty?
      ob_puts ""
      ob_puts "### Removed"
      ob_puts ""
      ob_puts "| Endpoint | Location |"
      ob_puts "| -------- | -------- |"
      result[:removed].each do |endpoint|
        ob_puts "| #{markdown_endpoint(endpoint)} | #{markdown_location(endpoint)} |"
      end
    end

    unless result[:changed].empty?
      ob_puts ""
      ob_puts "### Changed"
      ob_puts ""
      ob_puts "| Endpoint | Change | Location |"
      ob_puts "| -------- | ------ | -------- |"
      result[:changed].zip(result[:changes]) do |endpoint, change|
        ob_puts "| #{markdown_endpoint(endpoint)} | #{markdown_change(change)} | #{markdown_location(endpoint)} |"
      end
    end
  end

  private def markdown_endpoint(endpoint : Endpoint) : String
    markdown_code_span(sanitize_code_span_cell("#{endpoint.method} #{endpoint.url}"))
  end

  private def markdown_params(params : Array(ParamRef)) : String
    return "-" if params.empty?
    params.join(" ") { |param| markdown_code_span(sanitize_code_span_cell("#{param.name} (#{param.param_type})")) }
  end

  private def markdown_location(endpoint : Endpoint) : String
    code_path = endpoint.details.code_paths.first?
    return "-" unless code_path
    location = code_path.line ? "#{code_path.path}:#{code_path.line}" : code_path.path
    sanitize_text_cell(location)
  end

  private def markdown_change(change : Change) : String
    parts = [] of String
    parts << "**auth tag removed**" if change.auth_removed?
    parts << "added #{markdown_params(change.params_added)}" unless change.params_added.empty?
    parts << "removed #{markdown_params(change.params_removed)}" unless change.params_removed.empty?
    change.tags_added.each { |tag| parts << "tag #{markdown_code_span(sanitize_code_span_cell(tag))} added" }
    change.tags_removed.each do |tag|
      parts << "tag #{markdown_code_span(sanitize_code_span_cell(tag))} removed" unless tag == AUTH_TAG
    end
    parts.join("<br>")
  end

  # Code scanning annotations for the new surface only. A removed route has
  # no line in the tree being reviewed to annotate, and a param that went
  # away narrows the surface, so neither is reported here — the text, JSON
  # and markdown reports still list both.
  def print_sarif(result : Result)
    log = Sarif::Builder.build do |b|
      b.run("OWASP Noir", Noir::VERSION) do |r|
        r.information_uri("https://github.com/owasp-noir/noir")
        r.invocation(execution_successful: analyzer_failures.empty?)

        r.rule("diff-endpoint-added",
          name: "Endpoint Added",
          short_description: "A new endpoint is reachable",
          full_description: "This change adds an endpoint that did not exist in the revision it is compared against.",
          level: Sarif::Level::Note,
          help_uri: "https://owasp-noir.github.io/noir/usage/more_features/diff/")
        r.rule("diff-params-added",
          name: "Parameters Added",
          short_description: "An existing endpoint accepts new parameters",
          full_description: "This change makes an existing endpoint read parameters it did not read before.",
          level: Sarif::Level::Note,
          help_uri: "https://owasp-noir.github.io/noir/usage/more_features/diff/")
        r.rule("diff-auth-removed",
          name: "Auth Removed",
          short_description: "An endpoint lost its authentication",
          full_description: "The endpoint carried an auth tag in the compared revision and no longer does, so it may now be reachable without authentication.",
          level: Sarif::Level::Warning,
          help_uri: "https://owasp-noir.github.io/noir/usage/more_features/diff/")

        result[:added].each do |endpoint|
          sarif_result(r, endpoint, "diff-endpoint-added", Sarif::Level::Note,
            "New endpoint #{endpoint.method} #{endpoint.url}#{sarif_params(endpoint.params.map { |p| ParamRef.new(p.name, p.param_type) })}")
        end

        result[:changed].zip(result[:changes]) do |endpoint, change|
          if change.auth_removed?
            sarif_result(r, endpoint, "diff-auth-removed", Sarif::Level::Warning,
              "#{endpoint.method} #{endpoint.url} no longer has an auth tag")
          end
          unless change.params_added.empty?
            sarif_result(r, endpoint, "diff-params-added", Sarif::Level::Note,
              "#{endpoint.method} #{endpoint.url} accepts new parameters: #{sarif_param_list(change.params_added)}")
          end
        end
      end
    end
    ob_puts log.to_json
  end

  private def sarif_result(run, endpoint : Endpoint, rule_id : String, level : Sarif::Level, message : String)
    run.result do |rb|
      rb.message(message)
      rb.rule_id(rule_id)
      rb.level(level)
      endpoint.details.code_paths.each do |code_path|
        rb.location(uri: code_path.path, start_line: code_path.line)
      end
    end
  end

  private def sarif_params(params : Array(ParamRef)) : String
    params.empty? ? "" : " (Parameters: #{sarif_param_list(params)})"
  end

  private def sarif_param_list(params : Array(ParamRef)) : String
    params.join(", ") { |param| "#{param.param_type}: #{param.name}" }
  end
end
