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
            json_obj = JSON.parse(content)

            begin
              children = json_obj["children"].as_h
              if children.size > 0
                process_node(children)
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

    def process_node(children)
      # TODO..
    end
  end
end
