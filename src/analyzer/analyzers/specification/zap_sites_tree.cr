require "../../engines/specification_engine"
require "uri"

module Analyzer::Specification
  class ZapSitesTree < SpecificationEngine
    analyzer_for "zap_sites_tree"

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::ZAP_SITES_TREE) do |sites_tree, details|
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
          uri = begin
            URI.parse(path)
          rescue e
            logger.debug "Failed to parse ZAP site URL '#{path}': #{e}"
            nil
          end

          if uri
            params = [] of Param

            # A ZAP sites tree stores the URL a node was reached with, query
            # string included. Only `uri.path` was kept, so every query
            # parameter ZAP had already discovered was thrown away — the node
            # for `/search?q=noir&page=2` produced a bare `/search` with no
            # params at all.
            if query = uri.query
              add_named_params(query, "query", params)
            end

            if data = node["data"]?.try(&.as_s?)
              add_named_params(data, "form", params)
            end

            @result << Endpoint.new(uri.path, method, params, details)
          end
        end
      end

      if children = node["children"]?.try(&.as_a?)
        children.each do |child|
          process_node(child, details)
        end
      end
    end

    # Splits an `a=1&b=2` payload into named params of `param_type`, skipping
    # blanks and repeats.
    private def add_named_params(payload : String, param_type : String, params : Array(Param))
      payload.split('&').each do |pair|
        name = pair.split('=', 2).first.strip
        next if name.empty?
        next if params.any? { |existing| existing.name == name && existing.param_type == param_type }
        params << Param.new(name, "", param_type)
      end
    end
  end
end
