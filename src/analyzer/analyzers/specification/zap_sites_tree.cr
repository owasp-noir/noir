require "../../../models/analyzer"

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
      puts 1
      if node.is_a?(Hash) && node.has_key?("url") && node.has_key?("method")
        path = node["url"].as_s
        method = node["method"].as_s.upcase || "GET"
        if path != ""
          puts path, method
        end
      end

      puts 2

      if node.is_a?(Hash) && node.has_key?("children")
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
