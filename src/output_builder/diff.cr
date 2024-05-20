require "../models/output_builder"
require "../models/endpoint"

require "json"
require "yaml"

class OutputBuilderDiff < OutputBuilder
  def diff(new_endpoints : Array(Endpoint), old_endpoints : Array(Endpoint))
    added = new_endpoints - old_endpoints
    removed = old_endpoints - new_endpoints
    changed = new_endpoints & old_endpoints

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