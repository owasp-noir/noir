require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderMermaid < OutputBuilder
  def print(endpoints : Array(Endpoint))
    build_mindmap(endpoints)
  end

  def print(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult))
    build_mindmap(endpoints)
  end

  private def build_mindmap(endpoints : Array(Endpoint))
    ob_puts "mindmap"
    ob_puts "  root((/))"

    # Build hierarchical structure
    tree = build_path_tree(endpoints)

    # Output the tree with proper formatting
    output_tree(tree, 2)
  end

  # Simple tree node structure
  class TreeNode
    property children : Hash(String, TreeNode)
    property endpoints : Array(Endpoint)

    def initialize
      @children = {} of String => TreeNode
      @endpoints = [] of Endpoint
    end
  end

  private def build_path_tree(endpoints : Array(Endpoint))
    root = TreeNode.new
    endpoints.each do |endpoint|
      # Parse the URL path
      path = endpoint.url
      # Remove query parameters if any
      if path.includes?("?")
        path = path.split("?")[0]
      end
      # Handle root path
      if path == "/" || path == ""
        root.endpoints << endpoint
        next
      end
      # Split path into segments
      segments = path.split("/").reject(&.empty?)
      # Navigate/create tree structure
      current_node = root
      segments.each do |segment|
        # Sanitize segment for Mermaid compatibility
        sanitized_segment = sanitize_segment(segment)
        if !current_node.children.has_key?(sanitized_segment)
          current_node.children[sanitized_segment] = TreeNode.new
        end
        current_node = current_node.children[sanitized_segment]
      end
      # Add endpoint to the final node
      current_node.endpoints << endpoint
    end
    root
  end

  private def sanitize_segment(segment : String) : String
    # Replace invalid characters with underscore and ensure valid starting character
    sanitized = segment.gsub(/[^a-zA-Z0-9_]/, "_")
    # If starts with a number, prepend 'path_'
    if sanitized =~ /^\d/
      sanitized = "path_#{sanitized}"
    end
    # Ensure non-empty and unique
    sanitized.empty? ? "unnamed" : sanitized
  end

  private def output_tree(node : TreeNode, indent : Int32)
    # Output endpoints for this node
    node.endpoints.each do |endpoint|
      indent_str = "  " * indent
      # Format endpoint with method and URL, add [websocket] if applicable
      endpoint_label = "#{endpoint.method} #{endpoint.url}"
      endpoint_label += " [websocket]" if endpoint.protocol == "websocket"
      ob_puts "#{indent_str}#{endpoint_label}"

      # Get parameters grouped by type
      params_hash = endpoint.params_to_hash

      # Output headers
      unless params_hash["header"].empty?
        headers_indent = "  " * (indent + 1)
        ob_puts "#{headers_indent}headers"
        params_hash["header"].keys.sort.each do |header|
          header_indent = "  " * (indent + 2)
          ob_puts "#{header_indent}#{sanitize_segment(header)}"
        end
      end

      # Output cookies
      unless params_hash["cookie"].empty?
        cookies_indent = "  " * (indent + 1)
        ob_puts "#{cookies_indent}cookies"
        params_hash["cookie"].keys.sort.each do |cookie|
          cookie_indent = "  " * (indent + 2)
          ob_puts "#{cookie_indent}#{sanitize_segment(cookie)}"
        end
      end

      # Output body parameters (json, form, query)
      body_params = {} of String => String
      ["json", "form", "query"].each do |param_type|
        params_hash[param_type].each do |key, value|
          body_params[key] = value
        end
      end
      unless body_params.empty?
        body_indent = "  " * (indent + 1)
        ob_puts "#{body_indent}body"
        body_params.keys.sort.each do |param|
          param_indent = "  " * (indent + 2)
          ob_puts "#{param_indent}#{sanitize_segment(param)}"
        end
      end
    end

    # Output children nodes recursively
    sorted_keys = node.children.keys.sort
    sorted_keys.each do |segment|
      indent_str = "  " * indent
      ob_puts "#{indent_str}#{segment}"
      output_tree(node.children[segment], indent + 1)
    end
  end
end
