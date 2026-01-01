require "../models/output_builder"
require "./diff"
require "../models/endpoint"

require "json"
require "yaml"
require "colorize"

class OutputBuilderDiff < OutputBuilder
  def diff(new_endpoints : Array(Endpoint), old_endpoints : Array(Endpoint))
    added = [] of Endpoint
    changed = [] of Endpoint
    removed = [] of Endpoint

    new_endpoints.each do |new_endpoint|
      matching_old_endpoint = old_endpoints.find { |old_endpoint| old_endpoint.url == new_endpoint.url && old_endpoint.method == new_endpoint.method }
      if matching_old_endpoint
        changed << new_endpoint unless new_endpoint == matching_old_endpoint
      else
        added << new_endpoint
      end
    end

    old_endpoints.each do |old_endpoint|
      matching_new_endpoint = new_endpoints.find { |new_endpoint| new_endpoint.url == old_endpoint.url && new_endpoint.method == old_endpoint.method }
      removed << old_endpoint unless matching_new_endpoint
    end

    {added: added, removed: removed, changed: changed}
  end

  def print(endpoints : Array(Endpoint), diff_app : NoirRunner)
    result = diff(endpoints, diff_app.endpoints)

    if result[:added].size > 0
      added_header = "============== Added ================".colorize(:green).toggle(@is_color)
      @logger.puts added_header
      OutputBuilderCommon.new(@options).print(result[:added])
    end

    if result[:removed].size > 0
      removed_header = "============== Removed ==============".colorize(:red).toggle(@is_color)
      @logger.puts "\n#{removed_header}"
      OutputBuilderCommon.new(@options).print(result[:removed])
    end

    if result[:changed].size > 0
      changed_header = "============== Changed ==============".colorize(:yellow).toggle(@is_color)
      @logger.puts "\n#{changed_header}"
      OutputBuilderCommon.new(@options).print(result[:changed])
    end
  end

  def print_json(endpoints : Array(Endpoint), diff_app : NoirRunner)
    result = diff(endpoints, diff_app.endpoints)
    @logger.puts "\n" + result.to_json
  end

  def print_yaml(endpoints : Array(Endpoint), diff_app : NoirRunner)
    result = diff(endpoints, diff_app.endpoints)
    @logger.puts "\n" + result.to_yaml
  end

  def print_toml(endpoints : Array(Endpoint), diff_app : NoirRunner)
    result = diff(endpoints, diff_app.endpoints)
    json_str = result.to_json
    json_obj = JSON.parse(json_str)
    toml_output = generate_toml_from_diff(json_obj.as_h)
    @logger.puts "\n" + toml_output
  end

  private def generate_toml_from_diff(data : Hash(String, JSON::Any)) : String
    result = String.build do |io|
      data.each do |section, endpoints|
        if endpoints.as_a.size > 0
          io << "[#{section}]\n"
          endpoints.as_a.each_with_index do |endpoint, _|
            io << "\n[[#{section}.endpoint]]\n"
            endpoint.as_h.each do |key, value|
              case value.raw
              when String, Int64, Float64, Bool
                io << "#{key} = #{toml_value(value)}\n"
              when Array
                io << "#{key} = ["
                items = value.as_a.map { |item| toml_value(item) }
                io << items.join(", ")
                io << "]\n"
              end
            end
          end
          io << "\n"
        end
      end
    end
    result
  end

  private def toml_value(value : JSON::Any) : String
    case raw = value.raw
    when String
      %("#{raw.gsub("\\", "\\\\").gsub("\"", "\\\"")}")
    when Int64, Float64
      raw.to_s
    when Bool
      raw.to_s
    when Nil
      %("")
    else
      %("#{raw}")
    end
  end
end
