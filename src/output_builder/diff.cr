require "../models/output_builder"
require "../models/endpoint"
require "../models/access"
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
    # `Access.compare` over the requirement on both sides. Tag names alone
    # miss a guard that kept its tag and lost a role. Left out of JSON and
    # YAML when empty, so a diff without such a change reads as before.
    @[JSON::Field(ignore_serialize: @access_widened.empty?)]
    @[YAML::Field(ignore_serialize: @access_widened.empty?)]
    getter access_widened : Array(Access::Clause) = [] of Access::Clause
    @[JSON::Field(ignore_serialize: @access_unverified.empty?)]
    @[YAML::Field(ignore_serialize: @access_unverified.empty?)]
    getter access_unverified : Array(Access::Clause) = [] of Access::Clause

    def initialize(@method : String, @url : String, @params_added : Array(ParamRef),
                   @params_removed : Array(ParamRef), @tags_added : Array(String),
                   @tags_removed : Array(String), @access_widened = [] of Access::Clause,
                   @access_unverified = [] of Access::Clause)
      @auth_removed = @tags_removed.includes?(AUTH_TAG)
    end

    def empty? : Bool
      params_added.empty? && params_removed.empty? && tags_added.empty? && tags_removed.empty? &&
        access_widened.empty? && access_unverified.empty?
    end
  end

  alias Result = NamedTuple(added: Array(Endpoint), removed: Array(Endpoint), changed: Array(Endpoint), changes: Array(Change))

  private alias RouteIdentity = {String, String, {String, String?, String?, String?}}

  def diff(new_endpoints : Array(Endpoint), old_endpoints : Array(Endpoint)) : Result
    added = [] of Endpoint
    changed = [] of Endpoint
    removed = [] of Endpoint
    changes = [] of Change

    # Indexed by address and origin instead of a `find` per endpoint, which made
    # the diff quadratic — a monorepo with a few thousand endpoints on each
    # side spent longer here than in either scan. `put_if_absent` keeps the
    # first endpoint for a key, the one `find` used to return.
    old_index = index_by_route(old_endpoints)
    new_index = index_by_route(new_endpoints)

    new_endpoints.each do |new_endpoint|
      if matching_old_endpoint = old_index[route_identity(new_endpoint)]?
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
      removed << old_endpoint unless new_index.has_key?(route_identity(old_endpoint))
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
    access = Access.compare(Access.of(old_endpoint), Access.of(new_endpoint))

    Change.new(
      method: new_endpoint.method,
      url: new_endpoint.url,
      params_added: new_params.reject { |key, _| old_params.has_key?(key) }.values,
      params_removed: old_params.reject { |key, _| new_params.has_key?(key) }.values,
      tags_added: new_tags - old_tags,
      tags_removed: old_tags - new_tags,
      access_widened: access.widened,
      access_unverified: access.unverified,
    )
  end

  private def param_index(endpoint : Endpoint) : Hash({String, String}, ParamRef)
    index = {} of {String, String} => ParamRef
    endpoint.params.each do |param|
      index.put_if_absent({param.name, param.request_type}) { ParamRef.new(param.name, param.param_type) }
    end
    index
  end

  private def route_identity(endpoint : Endpoint) : RouteIdentity
    {endpoint.url, endpoint.method, endpoint.details.origin_identity}
  end

  private def index_by_route(endpoints : Array(Endpoint)) : Hash(RouteIdentity, Endpoint)
    index = Hash(RouteIdentity, Endpoint).new(initial_capacity: endpoints.size)
    endpoints.each { |endpoint| index.put_if_absent(route_identity(endpoint), endpoint) }
    index
  end

  # How many findings each `--fail-on` category has in `result`.
  def self.gate_counts(result : Result) : Hash(String, Int32)
    {
      "added"          => result[:added].size,
      "removed"        => result[:removed].size,
      "changed"        => result[:changed].size,
      "auth-removed"   => result[:changes].count(&.auth_removed?),
      "access-widened" => result[:changes].count { |change| !change.access_widened.empty? },
    }
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
        ob_puts format_change(endpoint, change)
      end
    end
  end

  # The `+`/`-` rows under a changed endpoint. The auth and access lines come
  # first and in red because they are the ones a reviewer must not miss.
  private def format_change(endpoint : Endpoint, change : Change) : String
    rows = [] of {String, Symbol}
    rows << {"! auth tag removed", :red} if change.auth_removed?
    change.access_widened.each do |clause|
      rows << {"! access widened: no longer requires #{clause}, from #{declared(clause)}", :red}
    end
    rows << {"  now requires: #{requirement(Access.of(endpoint))}", :red} unless change.access_widened.empty?
    change.access_unverified.each { |clause| rows << {"~ access check changed: #{declared(clause)}", :yellow} }
    change.params_added.each { |param| rows << {"+ #{param.param_type}: #{param.name}", :green} }
    change.params_removed.each { |param| rows << {"- #{param.param_type}: #{param.name}", :red} }
    change.tags_added.each { |tag| rows << {"+ tag: #{tag}", :green} }
    change.tags_removed.each { |tag| rows << {"- tag: #{tag}", :red} unless tag == AUTH_TAG }
    rows.join("\n") { |(text, color)| "  #{escape_control_chars(text).colorize(color).toggle(@is_color)}" }
  end

  private def declared(clause : Access::Clause) : String
    path = clause.path
    return clause.source unless path
    "#{clause.source} (#{clause.line ? "#{path}:#{clause.line}" : path})"
  end

  # Unread clauses print as `unresolved` alike, so they are shown once.
  private def requirement(clauses : Array(Access::Clause)) : String
    clauses.empty? ? "no guard found" : clauses.map(&.to_s).uniq!.join(" & ")
  end

  private def format_section_header(icon : String, text : String, count : Int32, color : Symbol) : String
    " #{icon} #{text} (#{count}) ".center(40, '─').colorize(color).toggle(@is_color).to_s
  end

  # The structured diff carries `errors` as `-f json` does: an analyzer that
  # failed on the new side otherwise reads as its endpoints being removed.
  private def document(result : Result)
    result.merge(errors: analyzer_failures)
  end

  def print_json(result : Result)
    ob_puts document(result).to_json
  end

  def print_yaml(result : Result)
    ob_puts document(result).to_yaml
  end

  def print_toml(result : Result)
    json_str = document(result).to_json
    json_obj = JSON.parse(json_str)
    toml_output = generate_toml_from_diff(json_obj.as_h)
    ob_puts toml_output
  end

  private def generate_toml_from_diff(data : Hash(String, JSON::Any)) : String
    result = String.build do |io|
      data.each do |section, entries|
        if section == "errors"
          # `[[errors]]`, the shape `-f toml` gives them.
          entries.as_a.each { |entry| io << "\n[[errors]]\n" << generate_table_content(entry.as_h) }
        elsif !entries.as_a.empty?
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
    widened = result[:changed].zip(result[:changes]).reject { |(_, change)| change.access_widened.empty? }

    ob_puts "## Attack surface diff"
    ob_puts ""
    unless analyzer_failures.empty?
      ob_puts "### :warning: Analyzer failures"
      ob_puts ""
      ob_puts "These analyzers failed or skipped files, so endpoints may be missing from either side of this diff."
      ob_puts ""
      ob_puts "| Tech | Error |"
      ob_puts "| ---- | ----- |"
      analyzer_failures.each do |failure|
        ob_puts "| #{markdown_code_span(sanitize_code_span_cell(failure.tech))} | #{sanitize_text_cell(failure.message)} |"
      end
      ob_puts ""
    end
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

    unless widened.empty?
      ob_puts ""
      ob_puts "### :warning: Access widened"
      ob_puts ""
      ob_puts "These routes no longer require something they required before this change."
      ob_puts ""
      ob_puts "| Endpoint | No longer requires | Declared by | Now requires |"
      ob_puts "| -------- | ------------------ | ----------- | ------------ |"
      widened.each do |(endpoint, change)|
        now = markdown_code_span(sanitize_code_span_cell(requirement(Access.of(endpoint))))
        change.access_widened.each do |clause|
          ob_puts "| #{markdown_endpoint(endpoint)} | #{markdown_code_span(sanitize_code_span_cell(clause.to_s))} | #{sanitize_text_cell(declared(clause))} | #{now} |"
        end
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
    change.access_widened.each do |clause|
      parts << "**access widened**: no longer requires #{markdown_code_span(sanitize_code_span_cell(clause.to_s))}"
    end
    change.access_unverified.each do |clause|
      parts << "access check changed: #{markdown_code_span(sanitize_code_span_cell(clause.source))}"
    end
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
        # Registered only when used, so a diff without an access change keeps
        # the rule list it had before these rules existed.
        if result[:changes].any? { |change| !change.access_widened.empty? }
          r.rule("diff-access-widened",
            name: "Access Widened",
            short_description: "An endpoint requires less than it did",
            full_description: "A requirement the endpoint had in the compared revision is no longer implied by its current guards, so more callers may reach it.",
            level: Sarif::Level::Warning,
            help_uri: "https://owasp-noir.github.io/noir/usage/more_features/diff/")
        end
        if result[:changes].any? { |change| !change.access_unverified.empty? }
          r.rule("diff-access-unverified",
            name: "Access Check Changed",
            short_description: "An access check noir cannot read changed",
            full_description: "The endpoint keeps a guard noir could not read, but its text differs from the compared revision, so whether it still refuses the same callers is unverified.",
            level: Sarif::Level::Note,
            help_uri: "https://owasp-noir.github.io/noir/usage/more_features/diff/")
        end

        result[:added].each do |endpoint|
          sarif_result(r, endpoint, "diff-endpoint-added", Sarif::Level::Note,
            "New endpoint #{endpoint.method} #{endpoint.url}#{sarif_params(endpoint.params.map { |p| ParamRef.new(p.name, p.param_type) })}")
        end

        result[:changed].zip(result[:changes]) do |endpoint, change|
          if change.auth_removed?
            sarif_result(r, endpoint, "diff-auth-removed", Sarif::Level::Warning,
              "#{endpoint.method} #{endpoint.url} no longer has an auth tag")
          end
          unless change.access_widened.empty?
            lost = change.access_widened.join("; ") { |clause| "#{clause}, from #{declared(clause)}" }
            sarif_result(r, endpoint, "diff-access-widened", Sarif::Level::Warning,
              "#{endpoint.method} #{endpoint.url} no longer requires #{lost}. Now requires: #{requirement(Access.of(endpoint))}")
          end
          change.access_unverified.each do |clause|
            sarif_result(r, endpoint, "diff-access-unverified", Sarif::Level::Note,
              "#{endpoint.method} #{endpoint.url} access check changed: #{declared(clause)}")
          end
          unless change.params_added.empty?
            sarif_result(r, endpoint, "diff-params-added", Sarif::Level::Note,
              "#{endpoint.method} #{endpoint.url} accepts new parameters: #{sarif_param_list(change.params_added)}")
          end
        end
      end
    end
    ob_puts sarif_with_srcroot(log).to_json
  end

  private def sarif_result(run, endpoint : Endpoint, rule_id : String, level : Sarif::Level, message : String)
    run.result do |rb|
      rb.message(message)
      rb.rule_id(rule_id)
      rb.level(level)
      endpoint.details.code_paths.each do |code_path|
        rb.location(uri: sarif_uri(code_path.path), start_line: code_path.line)
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
