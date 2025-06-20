require "../../../models/analyzer"
require "markd" # Changed from "markdown"
require "json" # For parsing request body examples if they are in JSON format

module Analyzer::Specification
  class ApiBlueprint < Analyzer
    # Represents a node in the Markd AST
    # Assuming Markd::Node is the base type for AST nodes.
    # This might need to be Markd::Block or Markd::Inline if those are distinct bases.
    alias AstNode = Markd::Node

    def analyze
      locator = CodeLocator.instance
      apib_files = locator.all("apib")

      if apib_files.is_a?(Array(String))
        apib_files.each do |apib_file|
          if File.exists?(apib_file)
            @logger.debug "Processing API Blueprint file: #{apib_file}"
            details = Details.new(PathInfo.new(apib_file))
            content = File.read(apib_file, encoding: "utf-8", invalid: :skip)

            begin
              # Assuming Markd.parse exists and returns a root document node
              doc = Markd.parse(content)
              extract_endpoints_from_ast(doc, details)
            rescue e
              @logger.error "Failed to parse Markdown for #{apib_file} with Markd: #{e.message}"
              @logger.debug_sub e
            end
          end
        end
      end

      @result
    end

    # Assuming the root node from Markd.parse is compatible with AstNode (Markd::Node)
    # and that it has a 'walk' method.
    private def extract_endpoints_from_ast(doc : AstNode, details : Details)
      current_resource_uri = ""
      current_resource_params = [] of Param

      # Assuming 'walk' method signature is similar: |node, entering|
      doc.walk do |node, entering|
        if entering
          case node
          # Assuming Heading node type is Markd::Node::Heading or Markd::Block::Heading
          # For now, let's try Markd::Node::Heading
          when Markd::Node::Heading
            level = node.level # Assuming .level exists
            text = extract_text_from_node(node).strip

            if level == 2 && text.starts_with?("Group ")
              @logger.debug "Found Resource Group: #{text}"
            elsif level == 3 # Resource
              match = text.match(/^(.*)\[(.*)\]$/)
              if match && match.size == 3
                current_resource_uri = match[2].strip
                current_resource_params = [] of Param
                @logger.debug "Found Resource: #{match[1].strip} - URI: #{current_resource_uri}"
              else
                @logger.warn "Could not parse resource heading: #{text}"
              end
            elsif level == 4 && !current_resource_uri.empty? # Action
              match = text.match(/^(.*)\[(.*)\]$/)
              if match && match.size == 3
                action_name = match[1].strip
                http_method = match[2].strip.upcase
                @logger.debug "Found Action: #{action_name} - Method: #{http_method} for Resource URI: #{current_resource_uri}"

                action_params = current_resource_params.dup
                @result << Endpoint.new(@url + current_resource_uri, http_method, action_params, details)
              else
                @logger.warn "Could not parse action heading: #{text}"
              end
            end
          # Assuming List node type is Markd::Node::List or Markd::Block::List
          when Markd::Node::List
            # Placeholder for more detailed list parsing (parameters, request bodies)
            # This logic would need significant adaptation based on how Markd structures
            # list items, their children, and how to extract MSON or code blocks.
            pass
          end
        end
      end
    end

    # This function needs to be robust to how Markd structures its AST,
    # especially for inline elements within a heading.
    private def extract_text_from_node(node : AstNode) : String
      buffer = IO::Memory.new
      # Assuming node responds to each_child or children
      # If walk is available on all nodes, that could also be used.
      # For now, assuming each_child iterates over direct children.
      node.each_child do |child|
        case child
        # Assuming Text node is Markd::Node::Text or Markd::Inline::Text
        when Markd::Node::Text
          buffer << child.literal # Assuming .literal for text content
        # Assuming Code node for inline code is Markd::Node::Code or Markd::Inline::Code
        when Markd::Node::Code
          buffer << child.literal # Assuming .literal for code content
        # Assuming these inline formatting nodes exist and also have children or a text extraction method
        when Markd::Node::Emphasis, Markd::Node::Strong, Markd::Node::Link # , Markd::Node::Image (image alt text)
          # Recurse to get text from children of these inline nodes
          buffer << extract_text_from_node(child)
        else
          # For other unexpected child types within a heading, this might need adjustment.
          # Some parsers might have all text content directly in a 'text_content' method of the parent.
        end
      end
      buffer.to_s
    end

  end
end
