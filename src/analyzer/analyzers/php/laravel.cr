require "../../../models/analyzer"
require "../../../models/endpoint"
require "../../../utils/utils"
require "log"

# TODO: Need to define or import Param, PathInfo, Details if not globally available
# For now, assuming they are similar to how they are used in the php_pure analyzer.
# Might need to adjust require paths or definitions.

module Analyzer::Php
  class LaravelAnalyzer < Analyzer
    Log = ::Log.for(self)

    # Regex to capture simple routes like Route::get('/path', ...);
    # Captures: 1=method, 2=path, 3=handler
    # Improved to handle various quote types and array/closure handlers
    ROUTE_REGEX = /Route::(get|post|put|patch|delete|options|any|match)\s*\(\s*['"]([^'"]+)['"]\s*,\s*(?:\[[^\]]+\]|function\s*\(.*?\)|['"]([^'"]+)['"]|([a-zA-Z0-9_\:]+::class))\s*\)/i

    # Regex for Route::resource or Route::apiResource
    # Captures: 1=type (resource or apiResource), 2=path, 3=controller
    RESOURCE_ROUTE_REGEX = /Route::(resource|apiResource)\s*\(\s*['"]([^'"]+)['"]\s*,\s*['"]?([^'"\s]+)['"]?\s*\)/i

    # Regex for controller actions like 'ControllerName@methodName' or [ControllerName::class, 'methodName']
    CONTROLLER_ACTION_REGEX = /(?:['"]([A-Za-z0-9_\\]+)@([a-zA-Z_][a-zA-Z0-9_]*)['"]|\[\s*([A-Za-z0-9_\\]+::class)\s*,\s*['"]([a-zA-Z_][a-zA-Z0-9_]*)['"]\s*\])/

    # Regex for parameters in controller methods or request objects
    # e.g., Request $request, string $id, MyFormRequest $formRequest
    # e.g., $request->input('name'), $request->query('id')
    REQUEST_PARAM_REGEX = /\$request->(?:input|query|post|get|route)\s*\(\s*['"]([^'"]+)['"]\s*(?:,[^)]*)?\)/
    METHOD_PARAM_REGEX = /(?:[A-Za-z0-9_\\]+\s+)?\$([a-zA-Z_][a-zA-Z0-9_]*)/i # Captures variable names like $id, $user
    FORM_REQUEST_PARAM_REGEX = /([A-Z][a-zA-Z0-9_]*Request)\s+\$([a-zA-Z_][a-zA-Z0-9_]*)/ # Captures FormRequest type hints


    def analyze
      Log.info "Starting Laravel analysis for path: #{@base_path}"
      endpoints = [] of Endpoint

      route_files = ["routes/web.php", "routes/api.php"]
      route_files.each do |route_file_name|
        full_route_path = File.join(@base_path, route_file_name)
        Log.debug "Checking route file: #{full_route_path}"
        if File.exists?(full_route_path)
          Log.info "Processing route file: #{full_route_path}"
          content = File.read(full_route_path, encoding: "utf-8", invalid: :skip)
          endpoints.concat(parse_routes_from_content(content, route_file_name))
        else
          Log.debug "Route file not found: #{full_route_path}"
        end
      end

      # Deduplicate endpoints (e.g. if 'ANY' method was used or multiple paths resolve similarly)
      # This is a basic deduplication, might need more sophisticated logic
      @result = endpoints.uniq { |ep| {ep.path, ep.method, ep.params_query.map(&.name).sort, ep.params_body.map(&.name).sort} }
      Log.info "Laravel analysis complete. Found #{@result.size} unique endpoints."
      Fiber.yield # Important for concurrency if used
      @result
    end

    private def parse_routes_from_content(content : String, source_file : String)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(source_file)) # Generic details for now

      content.each_line do |line|
        line = line.strip

        # Standard routes: Route::get, Route::post, etc.
        ROUTE_REGEX.scan(line) do |match|
          http_method = match[1].upcase
          path = match[2]
          handler = match[3]? || match[4]? # Handler can be Controller@action or Controller::class

          # If method is ANY, create endpoints for common methods
          methods_to_add = if http_method == "ANY"
                             ["GET", "POST", "PUT", "DELETE"]
                           else
                             [http_method]
                           end

          methods_to_add.each do |m_method|
            params_query = [] of Param
            params_body = [] of Param
            extract_path_params(path).each { |p_name| params_query << Param.new(p_name, "", "path") }

            if handler && !handler.strip.empty? && (handler.includes?("@") || handler.includes?("::class"))
              controller_params = parse_controller_action(handler, m_method)
              params_query.concat(controller_params.select { |p| p.in == "query" || p.in == "path" })
              params_body.concat(controller_params.select { |p| p.in == "form" || p.in == "body" }) # Assuming "form" for POST, "body" for others
            end

            # Ensure path params from route definition are included
            path_params_from_route = extract_path_params(path).map { |p_name| Param.new(p_name, "", "path") }
            params_query.concat(path_params_from_route)
            params_query = params_query.uniq(&.name)


            endpoints << Endpoint.new(normalize_path(path), m_method, params_query, params_body, details)
            Log.debug "Found route: #{m_method} #{normalize_path(path)} from handler: #{handler}"
          end
        end

        # Resource routes: Route::resource, Route::apiResource
        RESOURCE_ROUTE_REGEX.scan(line) do |match|
          type = match[1] # "resource" or "apiResource"
          base_path = normalize_path(match[2])
          controller_name = match[3] # Just the controller name, namespace assumed or needs resolving

          resource_methods = if type == "apiResource"
                               [
                                 {method: "GET", path: base_path, action: "index"},
                                 {method: "POST", path: base_path, action: "store"},
                                 {method: "GET", path: "#{base_path}/{#{singularize(base_path.split('/').last)}}", action: "show"},
                                 {method: "PUT", path: "#{base_path}/{#{singularize(base_path.split('/').last)}}", action: "update"},
                                 {method: "PATCH", path: "#{base_path}/{#{singularize(base_path.split('/').last)}}", action: "update"}, # Often PUT/PATCH point to same method
                                 {method: "DELETE", path: "#{base_path}/{#{singularize(base_path.split('/').last)}}", action: "destroy"},
                               ]
                             else # "resource"
                               [
                                 {method: "GET", path: base_path, action: "index"},
                                 {method: "GET", path: "#{base_path}/create", action: "create"},
                                 {method: "POST", path: base_path, action: "store"},
                                 {method: "GET", path: "#{base_path}/{#{singularize(base_path.split('/').last)}}", action: "show"},
                                 {method: "GET", path: "#{base_path}/{#{singularize(base_path.split('/').last)}}/edit", action: "edit"},
                                 {method: "PUT", path: "#{base_path}/{#{singularize(base_path.split('/').last)}}", action: "update"},
                                 {method: "PATCH", path: "#{base_path}/{#{singularize(base_path.split('/').last)}}", action: "update"},
                                 {method: "DELETE", path: "#{base_path}/{#{singularize(base_path.split('/').last)}}", action: "destroy"},
                               ]
                             end

          resource_methods.each do |res_route|
            params_query = [] of Param
            params_body = [] of Param

            extract_path_params(res_route[:path]).each { |p_name| params_query << Param.new(p_name, "", "path") }

            full_controller_action = "#{controller_name}@#{res_route[:action]}"
            controller_params = parse_controller_action(full_controller_action, res_route[:method])
            params_query.concat(controller_params.select { |p| p.in == "query" || p.in == "path" })
            params_body.concat(controller_params.select { |p| p.in == "form" || p.in == "body" })

            path_params_from_route = extract_path_params(res_route[:path]).map { |p_name| Param.new(p_name, "", "path") }
            params_query.concat(path_params_from_route)
            params_query = params_query.uniq(&.name)

            endpoints << Endpoint.new(res_route[:path], res_route[:method], params_query, params_body, details)
            Log.debug "Found resource route: #{res_route[:method]} #{res_route[:path]} -> #{full_controller_action}"
          end
        end
      end
      endpoints
    end

    private def parse_controller_action(handler_str : String, http_method : String)
      params = [] of Param
      Log.debug "Parsing controller action: #{handler_str}"

      actual_controller_name = ""
      method_name = ""

      CONTROLLER_ACTION_REGEX.scan(handler_str) do |match|
        if match[1]? && match[2]? # Format 'Controller@method'
          actual_controller_name = match[1]
          method_name = match[2]
        elsif match[3]? && match[4]? # Format [Controller::class, 'method']
          actual_controller_name = match[3].gsub("::class", "")
          method_name = match[4]
        end
      end

      return params if actual_controller_name.empty? || method_name.empty?

      # Construct path to controller file
      # Assumes default App\Http\Controllers namespace
      # Namespace can be different, this is a simplification
      controller_relative_path = actual_controller_name.gsub(/^App\Http\Controllers\/, "")
                                              .gsub(/^App\/, "") # Handle cases where App\ is used without Http\Controllers
                                              .gsub(/\/, "/") + ".php"
      controller_file_path = File.join(@base_path, "app", controller_relative_path)

      # A more robust way to find controller if not in app/Http/Controllers
      # This could involve searching in common controller directories or parsing composer.json for PSR-4 namespaces
      if !File.exists?(controller_file_path)
        # Try common alternative path if namespace was just App\MyController
         controller_file_path = File.join(@base_path, "app/Http/Controllers", controller_relative_path) # This line might be redundant if already tried
         # Try to find it if the namespace was just the class name (e.g. from a package or different structure)
         # This part needs a more sophisticated search or relies on a strict convention.
         # For now, we'll log and skip if not found in the primary location.
         Log.warn "Controller file not found at presumed path: #{controller_file_path} for handler #{handler_str}. Skipping parameter analysis from controller."
         return params
      end

      Log.info "Analyzing controller file: #{controller_file_path} for method #{method_name}"
      begin
        controller_content = File.read(controller_file_path, encoding: "utf-8", invalid: :skip)
        # Find the method definition
        # This regex is very basic and might fail with complex method signatures or comments
        method_def_regex = Regex.new(%r{function\s+#{method_name}\s*\(([^)]*)\)\s*(?:\{|;)}, Regex::Options::IGNORE_CASE)

        method_match = method_def_regex.match(controller_content)
        if method_match && method_match.captures.size > 0
          method_signature_params = method_match.captures[0].to_s.strip
          Log.debug "Method signature params string: '#{method_signature_params}'"

          # Extract params from method signature (e.g., string $id, Post $post)
          # This will capture type hints and variable names
          method_signature_params.split(',').each do |param_str|
            param_str = param_str.strip
            next if param_str.empty?

            # Check for FormRequest type hints
            form_request_match = FORM_REQUEST_PARAM_REGEX.match(param_str)
            if form_request_match
              form_request_class = form_request_match[1]
              Log.info "Found FormRequest: #{form_request_class} in method #{method_name}"
              # Attempt to parse rules from FormRequest
              params.concat(parse_form_request(form_request_class, http_method))
              next # Skip adding as a simple path/query param if it's a FormRequest
            end

            # For other parameters (route model binding or simple type hints)
            # Treat them as path parameters by default if they are not Request objects
            var_match = METHOD_PARAM_REGEX.match(param_str)
            if var_match && !param_str.downcase.includes?("request") # Avoid capturing Illuminate\Http\Request
              param_name = var_match[1]
              # These are often route parameters injected by Laravel
              params << Param.new(param_name, "", "path")
              Log.debug "Found method signature param (potential path param): #{param_name}"
            end
          end

          # Extract params from $request->input(), $request->query(), etc.
          # This needs to search within the method body, which is more complex.
          # For simplicity, we'll scan the whole controller content for now,
          # which is not ideal as it might pick up params from other methods.
          # A proper parser would isolate the method body.
          REQUEST_PARAM_REGEX.scan(controller_content) do |req_match|
            param_name = req_match[1]
            param_type = (http_method == "GET" || http_method == "DELETE") ? "query" : "form" # Simplified default
            # TODO: Differentiate $request->query vs $request->post for better accuracy
            # This regex captures the method (input, query, post) which could be used to refine 'param_type'

            # A more refined approach for param_type based on $request method:
            # e.g. if line includes $request->query, type is "query"
            # e.g. if line includes $request->post or $request->input on a POST/PUT, type is "form"

            params << Param.new(param_name, "", param_type)
            Log.debug "Found request param: #{param_name} (type: #{param_type})"
          end
        else
          Log.warn "Could not find method definition for '#{method_name}' in #{controller_file_path}"
        end
      rescue e : File::NotFoundError
        Log.warn "Controller file not found: #{controller_file_path}. Error: #{e.message}"
      rescue ex
        Log.error "Error parsing controller #{controller_file_path}: #{ex.message}"
      end

      params.uniq(&.name)
    end

    # Basic FormRequest parser - attempts to find and parse the rules() method.
    private def parse_form_request(form_request_class_name : String, http_method : String)
      params = [] of Param
      # Assumptions: FormRequests are in App\Http\Requests namespace
      form_request_relative_path = form_request_class_name.gsub(/^App\Http\Requests\/, "")
                                                      .gsub(/\/, "/") + ".php"
      form_request_file_path = File.join(@base_path, "app/Http/Requests", form_request_relative_path)

      if !File.exists?(form_request_file_path)
        # Try alternative if namespace was just App\Requests\MyRequest
         form_request_file_path = File.join(@base_path, "app", form_request_relative_path)
         if !File.exists?(form_request_file_path)
            Log.warn "FormRequest file not found: #{form_request_file_path}. Cannot parse rules."
            return params
         end
      end

      Log.info "Analyzing FormRequest file: #{form_request_file_path}"
      begin
        content = File.read(form_request_file_path, encoding: "utf-8", invalid: :skip)
        # Very basic regex to find keys in the rules() method's returned array
        # This will not handle complex logic within rules() but captures simple string keys.
        # Example: 'title' => 'required|unique:posts|max:255',
        rules_method_regex = /public\s+function\s+rules\s*\(\s*\)\s*(?::\s*array\s*)?\{[^}]*return\s*\[([^\]]*)\];/m
        rules_content_match = rules_method_regex.match(content)

        if rules_content_match && rules_content_match.captures.size > 0
          rules_array_content = rules_content_match.captures[0].to_s
          # Extract keys from the array-like string: 'keyname' => ... or "keyname" => ...
          param_name_regex = /['"]([^'"]+)['"]\s*=>/
          param_name_regex.scan(rules_array_content) do |key_match|
            param_name = key_match[1]
            # Determine if it's query or body param based on HTTP method (simplification)
            param_type = (http_method == "GET" || http_method == "DELETE") ? "query" : "form"
            params << Param.new(param_name, "", param_type)
            Log.debug "Found FormRequest rule param: #{param_name} (type: #{param_type})"
          end
        else
          Log.warn "Could not find or parse rules() method in #{form_request_file_path}"
        end
      rescue e : File::NotFoundError
        Log.warn "FormRequest file not found during parsing attempt: #{form_request_file_path}. Error: #{e.message}"
      rescue ex
        Log.error "Error parsing FormRequest #{form_request_file_path}: #{ex.message}"
      end
      params.uniq(&.name)
    end

    private def extract_path_params(path : String)
      params = [] of String
      path.scan(/\{([^\}]+)\}/) do |match|
        param_name = match[1]
        # Remove optional '?' and any regex constraints like ':.*' or ':id'
        param_name = param_name.gsub(/\?$/, "").split(':').first.to_s.strip
        params << param_name unless param_name.empty?
      end
      params.uniq
    end

    private def normalize_path(path : String)
      # Ensure path starts with a slash and remove trailing slashes if not root
      p = path.strip
      p = "/#{p}" unless p.starts_with?("/")
      p = p.gsub(/\/+$/, "") if p.size > 1 # Avoid removing slash if path is just "/"
      p = "/" if p.empty? # Handle case where path might become empty
      p
    end

    # Basic singularize helper for resource names (e.g., "users" -> "user")
    # This is very naive and won't handle irregular plurals.
    private def singularize(word : String)
      return word if word.empty?
      # Common cases
      if word.ends_with?("ies") && word.size > 3
        return word[0..-4] + "y"
      elsif word.ends_with?("s") && word.size > 1
        return word[0..-2]
      end
      word # Default to original word if no simple rule applies
    end

    def allow_patterns
      # Not directly used in this analyzer structure, but kept for compatibility if base class uses it
      [] of String
    end
  end
end
