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
    
    # Output the tree
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
        if !current_node.children.has_key?(segment)
          current_node.children[segment] = TreeNode.new
        end
        current_node = current_node.children[segment]
      end
      
      # Add endpoint to the final node
      current_node.endpoints << endpoint
    end
    
    root
  end

  private def output_tree(node : TreeNode, indent : Int32)
    # Output endpoints for this node
    node.endpoints.each do |endpoint|
      indent_str = " " * indent
      ob_puts "#{indent_str}#{endpoint.method} #{endpoint.url}"
      
      # Output parameters
      endpoint.params.each do |param|
        param_indent_str = " " * (indent + 2)
        ob_puts "#{param_indent_str}#{param.name}"
      end
    end
    
    # Output children nodes recursively
    sorted_keys = node.children.keys.sort
    sorted_keys.each do |segment|
      indent_str = " " * indent
      ob_puts "#{indent_str}#{segment}"
      output_tree(node.children[segment], indent + 2)
    end
  end
end