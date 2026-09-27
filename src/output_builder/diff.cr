require "../models/output_builder"
require "../models/endpoint"
require "./toml_serializer"

require "json"
require "yaml"
require "colorize"

class OutputBuilderDiff < OutputBuilder
  include OutputBuilderTomlSerializer

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

  def diff(new_endpoints : Array(Endpoint), old_endpoints : Array(Endpoint))
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

  def print(endpoints : Array(Endpoint), diff_app : NoirRunner)
    result = diff(endpoints, diff_app.endpoints)
    common = OutputBuilderCommon.new(@options)
    common.io = io

    if !result[:added].empty?
      ob_puts format_section_header("✚", "Added", result[:added].size, :green)
      common.print(result[:added])
    end

    if !result[:removed].empty?
      ob_puts "\n#{format_section_header("✖", "Removed", result[:removed].size, :red)}"
      common.print(result[:removed])
    end

    if !result[:changed].empty?
      ob_puts "\n#{format_section_header("≠", "Changed", result[:changed].size, :yellow)}"
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
    result = diff(endpoints, diff_app.endpoints)
    ob_puts result.to_json
  end

  def print_yaml(endpoints : Array(Endpoint), diff_app : NoirRunner)
    result = diff(endpoints, diff_app.endpoints)
    ob_puts result.to_yaml
  end

  def print_toml(endpoints : Array(Endpoint), diff_app : NoirRunner)
    result = diff(endpoints, diff_app.endpoints)
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
end
