require "../models/output_builder"
require "./diff"
require "../models/endpoint"

require "json"
require "yaml"

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
      @logger.puts "============== Added ================"
      OutputBuilderCommon.new(@options).print(result[:added])
    end

    if result[:removed].size > 0
      @logger.puts "\n============== Removed =============="
      OutputBuilderCommon.new(@options).print(result[:removed])
    end

    if result[:changed].size > 0
      @logger.puts "\n============== Changed =============="
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
end
