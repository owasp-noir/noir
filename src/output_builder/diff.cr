require "../models/output_builder"
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
    @logger.system "============== DIFF =============="
    result = diff(endpoints, diff_app.endpoints)

    result[:added].each do |endpoint|
      @logger.info "Added: #{endpoint.url} #{endpoint.method}"
    end

    result[:removed].each do |endpoint|
      @logger.info "Removed: #{endpoint.url} #{endpoint.method}"
    end

    result[:changed].each do |endpoint|
      @logger.info "Changed: #{endpoint.url} #{endpoint.method}"
    end
  end

  def print_json(endpoints : Array(Endpoint), diff_app : NoirRunner)
    @logger.system "============== DIFF (JSON) =============="
    result = diff(endpoints, diff_app.endpoints)

    puts result.to_json
  end

  def print_yaml(endpoints : Array(Endpoint), diff_app : NoirRunner)
    @logger.system "============== DIFF (YAML) =============="
    result = diff(endpoints, diff_app.endpoints)

    puts result.to_yaml
  end
end
