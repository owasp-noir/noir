require "../models/endpoint"
require "../minilexers/js_lexer"
require "../miniparsers/js_parser"

module Noir
  # JSRouteExtractor provides a unified interface for extracting routes from JavaScript files
  class JSRouteExtractor
    def self.extract_routes(file_path : String) : Array(Endpoint)
      return [] of Endpoint unless File.exists?(file_path)

      begin
        content = File.read(file_path)
        parser = JSParser.new(content)
        route_patterns = parser.parse_routes

        endpoints = [] of Endpoint
        route_patterns.each do |pattern|
          # Normalize HTTP method (e.g., DEL -> DELETE)
          normalized_method = normalize_http_method(pattern.method)
          endpoint = Endpoint.new(pattern.path, normalized_method)

          # Add path parameters detected in the URL
          pattern.params.each do |param|
            endpoint.push_param(param)
          end

          # Extract other parameters like body, query, etc. from the content around this route
          extract_params_from_context(content, pattern, endpoint)

          endpoints << endpoint
        end

        endpoints
      rescue e
        # If parser fails, return empty array
        [] of Endpoint
      end
    end

    # Normalize HTTP method names to standard format
    def self.normalize_http_method(method : String) : String
      method = method.upcase

      # Standardize HTTP methods
      case method
      when "DEL"
        return "DELETE"
      when "OPTIONS"
        return "OPTIONS"
      when "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "ALL"
        return method
      end

      # Return the original (uppercased) method if no specific normalization needed
      method
    end

    def self.extract_params_from_context(content : String, pattern : JSRoutePattern, endpoint : Endpoint)
      # Extract additional parameters from the route handler content
      # Look for the route declaration and then analyze the handler function
      method_name = pattern.method.downcase

      # Create possible method names for both dot notation and bracket notation
      method_variations = [method_name]

      # Handle the case where 'del' might be used instead of 'delete' in the code or vice versa
      if method_name == "delete"
        method_variations << "del"
      elsif method_name == "del"
        method_variations << "delete"
      end

      # Generate all possible route declarations with different syntax patterns
      route_declarations = [] of String
      method_variations.each do |method|
        # Standard method call with single quotes
        route_declarations << "#{method}('#{pattern.path}'"
        # Method call with double quotes
        route_declarations << "#{method}(\"#{pattern.path}\""
        # Method call with template literals
        route_declarations << "#{method}(`#{pattern.path}`"
      end

      # Find the index of any matching route declaration
      idx = nil
      route_declarations.each do |declaration|
        found_idx = content.index(declaration)
        if found_idx
          idx = found_idx
          break
        end
      end

      return unless idx

      # Find the opening brace of the handler function
      open_brace_idx = content.index("{", idx)
      return unless open_brace_idx

      # Extract the handler function body
      # (This is a simplified approach - a more robust approach would count braces)
      close_brace_idx = find_matching_brace(content, open_brace_idx)
      return unless close_brace_idx

      handler_body = content[open_brace_idx..close_brace_idx]

      # Now analyze the handler body for req.body, req.query, etc.
      extract_body_params(handler_body, endpoint)
      extract_query_params(handler_body, endpoint)
      extract_header_params(handler_body, endpoint)
      extract_cookie_params(handler_body, endpoint)
    end

    private def self.find_matching_brace(content : String, open_brace_idx : Int32) : Int32?
      brace_count = 1
      idx = open_brace_idx + 1

      while idx < content.size && brace_count > 0
        case content[idx]
        when '{'
          brace_count += 1
        when '}'
          brace_count -= 1
        end
        idx += 1

        # Return the position of the matching closing brace
        return idx - 1 if brace_count == 0
      end

      # No matching brace found
      nil
    end

    private def self.extract_body_params(handler_body : String, endpoint : Endpoint)
      # Look for req.body.X or const/let/var { X } = req.body
      # First check the destructuring pattern
      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*(?:req|request)\.body/) do |match|
        if match.size > 0
          params = match[1].split(",").map(&.strip)
          params.each do |param|
            clean_param = param.split("=").first.strip
            endpoint.push_param(Param.new(clean_param, "", "json")) unless clean_param.empty?
          end
        end
      end

      # Then check direct property access
      handler_body.scan(/(?:req|request)\.body\.(\w+)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "json"))
        end
      end
    end

    private def self.extract_query_params(handler_body : String, endpoint : Endpoint)
      # Look for req.query.X
      handler_body.scan(/(?:req|request)\.query\.(\w+)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "query"))
        end
      end
    end

    private def self.extract_header_params(handler_body : String, endpoint : Endpoint)
      # Look for req.headers['X'] or req.header('X')
      handler_body.scan(/(?:req|request)\.headers\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "header"))
        end
      end

      handler_body.scan(/(?:req|request)\.headers\.(\w+)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "header"))
        end
      end

      handler_body.scan(/(?:req|request)\.header\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "header"))
        end
      end
    end

    private def self.extract_cookie_params(handler_body : String, endpoint : Endpoint)
      # Look for req.cookies.X
      handler_body.scan(/(?:req|request)\.cookies\.(\w+)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "cookie"))
        end
      end
    end
  end
end
