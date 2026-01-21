require "../../../models/analyzer"
require "uri"

module Analyzer::Specification
  class ZapSitesTree < Analyzer
    def analyze
      locator = CodeLocator.instance
      sites_trees = locator.all("zap-sites-tree")

      if sites_trees.is_a?(Array(String))
        sites_trees.each do |sites_tree|
          if File.exists?(sites_tree)
            details = Details.new(PathInfo.new(sites_tree))
            content = File.read(sites_tree, encoding: "utf-8", invalid: :skip)
            yaml_obj = YAML.parse(content)

            begin
              children = yaml_obj.as_a
              children.each do |child|
                process_node(child, details)
              end
            rescue e
              @logger.debug "Exception of #{sites_tree}/paths"
              @logger.debug_sub e
            end
          end
        end
      end

      @result
    end

    def process_node(node, details)
      if node.as_h.has_key?("url") && node.as_h.has_key?("method")
        path = node["url"].as_s
        method = node["method"].as_s.upcase || "GET"

        if path != ""
          uri = URI.parse(path)
          params = [] of Param
          if node.as_h.has_key?("data")
            data = node["data"].as_s
            begin
              data.split("&").each do |param|
                param_name = param.split("=")[0]
                param = Param.new(param_name.to_s, "", "form")
                params << param
              end
            rescue
            end
          end

          @result << Endpoint.new(uri.path, method, params, details)
        end
      end

      if node.as_h.has_key?("children")
        children = node["children"].as_a
        if children.size > 0
          children.each do |child|
            process_node(child, details)
          end
        end
      end
    end
  end
end
