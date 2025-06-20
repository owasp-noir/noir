require "../../../models/analyzer"
require "markdown"
require "json" # For parsing request body examples if they are in JSON format

module Analyzer::Specification
  class ApiBlueprint < Analyzer
    # Represents a node in the Markdown AST
    alias MarkdownNode = Markdown::AST::Node

    def analyze
      locator = CodeLocator.instance
      # Assuming 'apib' will be the identifier for API Blueprint files
      apib_files = locator.all("apib")

      if apib_files.is_a?(Array(String))
        apib_files.each do |apib_file|
          if File.exists?(apib_file)
            @logger.debug "Processing API Blueprint file: #{apib_file}"
            details = Details.new(PathInfo.new(apib_file))
            content = File.read(apib_file, encoding: "utf-8", invalid: :skip)

            begin
              doc = Markdown.parse(content)
              extract_endpoints_from_ast(doc, details)
            rescue e
              @logger.error "Failed to parse Markdown for #{apib_file}: #{e.message}"
              @logger.debug_sub e
            end
          end
        end
      end

      @result
    end

    private def extract_endpoints_from_ast(doc : MarkdownNode, details : Details)
      current_resource_uri = ""
      current_resource_params = [] of Param

      doc.walk do |node, entering|
        if entering
          case node
          when Markdown::AST::Heading
            level = node.level
            text = extract_text_from_node(node).strip

            if level == 2 && text.starts_with?("Group ")
              # Resource Group, not directly used for endpoint extraction but good for structure
              @logger.debug "Found Resource Group: #{text}"
            elsif level == 3 # Resource
              match = text.match(/^(.*)\[(.*)\]$/)
              if match && match.size == 3
                current_resource_uri = match[2].strip
                current_resource_params = [] of Param # Reset params for new resource
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

                # Parameters for this action (combining resource params and action-specific params)
                action_params = current_resource_params.dup

                # Placeholder for finding parameters within the action's description
                # This would involve parsing list items for "+ Parameters" or request body definitions
                # For simplicity in this step, we are not fully parsing complex parameter definitions
                # A more robust solution would parse MSON or detailed request body structures

                @result << Endpoint.new(@url + current_resource_uri, http_method, action_params, details)
              else
                @logger.warn "Could not parse action heading: #{text}"
              end
            end
          when Markdown::AST::List # Potentially parameters or request/response definitions
            # This is where more detailed parsing of parameters, request bodies, etc. would go.
            # For example, looking for "+ Parameters" or "+ Request" list items.
            # The API Blueprint tutorial shows parameters defined like:
            # + Parameters
            #     + name (type) - description
            # And request bodies:
            # + Request (application/json)
            #         { ... }
            # This requires more sophisticated parsing of list item contents.
            # For now, we'll keep it simple and focus on path and method.
            # A full implementation would need to parse MSON within these sections.
            # Example: if a list item starts with "+ Parameters", iterate its children for param definitions.
            # If it starts with "+ Request", parse the content type and body.
            # This part is non-trivial due to the free-form nature of Markdown combined with MSON.
            # We'll rely on URI parameters if defined directly in the resource heading for now.
            # And assume basic request parameters might be described textually.
            # A more robust parser would need to handle MSON syntax.
            # Example:
            # node.each_child do |list_item_node|
            #   if list_item_node.is_a?(Markdown::AST::Item)
            #     item_text = extract_text_from_node(list_item_node).strip
            #     if item_text.starts_with?("+ Parameters")
            #       # Parse parameters from subsequent nested lists/items
            #     elsif item_text.starts_with?("Parameters") && node.parent.is_a?(Markdown::AST::Heading) && node.parent.as(Markdown::AST::Heading).level == 3
            #        # This is for URI parameters like /path/{id}
            #        # + Parameters
            #        #   + id (number) - description
            #        # This would update current_resource_params
            #     elsif item_text.starts_with?("+ Request")
            #       # Parse request body from a code block or subsequent text
            #     end
            #   end
            # end
            pass # Placeholder for more detailed list parsing
          end
        end
      end
    end

    private def extract_text_from_node(node : MarkdownNode) : String
      buffer = IO::Memory.new
      node.each_child do |child|
        case child
        when Markdown::AST::Text
          buffer << child.text
        when Markdown::AST::Code
          buffer << child.text # Or handle code blocks differently if needed
        when Markdown::AST::Emphasis, Markdown::AST::Strong, Markdown::AST::Link, Markdown::AST::Image
          # For these, we might want to recurse to get their text content
          buffer << extract_text_from_node(child)
        else
          # For other block types like lists or sub-headings within a heading's children (if possible)
          # you might need specific handling or recursion.
          # For now, we primarily expect Text nodes within simple headings.
        end
      end
      buffer.to_s
    end

  end
end
