require "../models/output_builder"
require "../models/endpoint"
require "./toml_serializer"

require "json"
require "yaml"
require "colorize"

class OutputBuilderDiff < OutputBuilder
  include OutputBuilderTomlSerializer

  def diff(new_endpoints : Array(Endpoint), old_endpoints : Array(Endpoint))
    added = [] of Endpoint
    changed = [] of Endpoint
    removed = [] of Endpoint

    # Indexed by (url, method) instead of a `find` per endpoint, which made
    # the diff quadratic — a monorepo with a few thousand endpoints on each
    # side spent longer here than in either scan. `put_if_absent` keeps the
    # first endpoint for a key, the one `find` used to return.
    old_index = index_by_route(old_endpoints)
    new_index = index_by_route(new_endpoints)

    new_endpoints.each do |new_endpoint|
      if matching_old_endpoint = old_index[{new_endpoint.url, new_endpoint.method}]?
        changed << new_endpoint unless new_endpoint == matching_old_endpoint
      else
        added << new_endpoint
      end
    end

    old_endpoints.each do |old_endpoint|
      removed << old_endpoint unless new_index.has_key?({old_endpoint.url, old_endpoint.method})
    end

    {added: added, removed: removed, changed: changed}
  end

  private def index_by_route(endpoints : Array(Endpoint)) : Hash({String, String}, Endpoint)
    index = Hash({String, String}, Endpoint).new(initial_capacity: endpoints.size)
    endpoints.each { |endpoint| index.put_if_absent({endpoint.url, endpoint.method}, endpoint) }
    index
  end

  def print(endpoints : Array(Endpoint), diff_app : NoirRunner)
    result = diff(endpoints, diff_app.endpoints)

    if !result[:added].empty?
      ob_puts format_section_header("✚", "Added", result[:added].size, :green)
      OutputBuilderCommon.new(@options).print(result[:added])
    end

    if !result[:removed].empty?
      ob_puts "\n#{format_section_header("✖", "Removed", result[:removed].size, :red)}"
      OutputBuilderCommon.new(@options).print(result[:removed])
    end

    if !result[:changed].empty?
      ob_puts "\n#{format_section_header("≠", "Changed", result[:changed].size, :yellow)}"
      OutputBuilderCommon.new(@options).print(result[:changed])
    end
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
      data.each do |section, endpoints|
        if !endpoints.as_a.empty?
          io << "[#{section}]\n"
          endpoints.as_a.each do |endpoint|
            io << "\n[[#{section}.endpoint]]\n"
            io << generate_table_content(endpoint.as_h)
          end
          io << "\n"
        end
      end
    end
    result
  end
end
