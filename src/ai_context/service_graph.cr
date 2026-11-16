require "digest/sha256"
require "./outbound_request"
require "../utils/route_matcher"

module NoirAIContext::ServiceGraph
  extend self

  def reference(endpoint : Endpoint) : ServiceEndpoint
    ServiceEndpoint.new(endpoint.details.project, endpoint.method, endpoint.url, endpoint.service_variant || variant(endpoint))
  end

  private def variant(endpoint : Endpoint) : String?
    return if endpoint.route_conditions.empty?
    conditions = endpoint.route_conditions.map { |param| {param.name, param.request_type, param.value} }.sort!
    Digest::SHA256.hexdigest(conditions.to_json)
  end

  def apply(endpoints : Array(Endpoint)) : Array(Endpoint)
    endpoints.each_with_index do |endpoint, index|
      endpoint.service_variant ||= variant(endpoint)
      endpoint.calls.clear
      endpoint.called_by.clear
      endpoints[index] = endpoint
    end
    served = endpoints.select { |endpoint| !endpoint.details.project.empty? && !endpoint.internal && !endpoint.non_http? }
    cache = Hash({String, String, String?, Bool}, Array(Noir::RouteMatcher::Match)).new
    endpoints.each do |caller|
      caller.ai_context.try(&.sinks).try &.each do |sink|
        next unless sink.kind == "outbound_http"
        targets = OutboundRequest.targets(sink)
        if targets.empty?
          caller.calls << ServiceCall.new(sink)
          next
        end
        targets.each do |target|
          unless url = target.url
            caller.calls << ServiceCall.new(sink)
            next
          end
          edges = [] of ServiceEdge
          unless caller.details.project.empty?
            matches = cache[{caller.details.project, url, target.method, target.template}] ||= begin
              candidates = served.select do |callee|
                callee.details.project != caller.details.project && compatible_hosts?(url, callee.url)
              end
              found = Noir::RouteMatcher.trace(candidates, target.method, url)
              if target.template && (shape = Noir::RouteMatcher.template_shape(url))
                candidates.each do |callee|
                  next unless Noir::RouteMatcher.method_serves?(callee.method, target.method)
                  next unless Noir::RouteMatcher.template_shape(callee.url) == shape
                  found << Noir::RouteMatcher::Match.new(callee, "template") unless found.any? { |match| reference(match.endpoint) == reference(callee) }
                end
              end
              found
            end
            matches.each do |match|
              # An all-path fallback alone is no evidence of a service target.
              if Noir::RouteMatcher.specificity(match.endpoint.url)[0] > 0
                next unless Noir::RouteMatcher.literal_anchor?(match.endpoint.url)
              end
              basis = absolute?(url) && absolute?(match.endpoint.url) ? "url" : "path"
              basis += "_#{target.template ? "template" : match.matched_by}"
              edges << ServiceEdge.new(reference(match.endpoint), basis, sink.path, sink.line)
              match.endpoint.called_by << ServiceEdge.new(reference(caller), basis, sink.path, sink.line)
            end
          end
          caller.calls << ServiceCall.new(sink, url, target.method, edges)
        end
      end
    end
    endpoints
  end

  private def absolute?(url : String) : Bool
    url.starts_with?("http://") || url.starts_with?("https://")
  end

  private def compatible_hosts?(url : String, route : String) : Bool
    return true unless absolute?(url) && absolute?(route)
    left = URI.parse(url)
    right = URI.parse(route)
    left.scheme == right.scheme && left.host.try(&.downcase) == right.host.try(&.downcase) &&
      (left.port || (left.scheme == "https" ? 443 : 80)) == (right.port || (right.scheme == "https" ? 443 : 80))
  rescue URI::Error
    false
  end
end
