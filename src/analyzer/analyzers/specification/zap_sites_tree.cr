require "../../engines/specification_engine"
require "uri"

module Analyzer::Specification
  class ZapSitesTree < SpecificationEngine
    def analyze
      each_spec_file_with_details("zap-sites-tree") do |sites_tree, details|
        content = read_file_content(sites_tree)
        yaml_obj = YAML.parse(content)

        children = yaml_obj.as_a
        children.each do |child|
          process_node(child, details)
        end
      end

      @result
    end

    def process_node(node, details)
      # Use safe accessors: a single malformed node (scalar child, non-array
      # `children`, non-string `method`) must skip that branch, not raise and
      # abort the whole sites-tree (the only rescue is at the file level).
      h = node.as_h?
      return unless h

      if h.has_key?("url") && h.has_key?("method")
        path = node["url"].as_s? || ""
        method = node["method"].as_s?.try(&.upcase) || "GET"

        if !path.empty?
          uri = URI.parse(path)
          params = [] of Param
          if data = node["data"]?.try(&.as_s?)
            begin
              data.split("&").each do |param|
                param_name = param.split("=")[0]
                params << Param.new(param_name.to_s, "", "form")
              end
            rescue e
              logger.debug "Failed to parse ZAP query params for #{path}: #{e}"
            end
          end

          @result << Endpoint.new(uri.path, method, params, details)
        end
      end

      if children = node["children"]?.try(&.as_a?)
        children.each do |child|
          process_node(child, details)
        end
      end
    end
  end
end
