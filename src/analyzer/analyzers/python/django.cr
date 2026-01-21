require "../../../models/analyzer"
require "./python"
require "json"

module Analyzer::Python
  class Django < Python
    # Base path for the Django project
    @django_base_path : ::String = ""
    @visited_url_paths = Hash(String, Bool).new

    # Regular expressions for extracting Django URL configurations
    REGEX_ROOT_URLCONF  = /\s*ROOT_URLCONF\s*=\s*r?['"]([^'"\\]*)['"]/
    REGEX_ROUTE_MAPPING = /(?:url|path|register)\s*\(\s*r?['"]([^"']*)['"][^,]*,\s*([^),]*)/
    REGEX_INCLUDE_URLS  = /include\s*\(\s*r?['"]([^'"\\]*)['"]/

    # Map request parameters to their respective fields
    REQUEST_PARAM_FIELD_MAP = {
      "GET"     => {["GET"], "query"},
      "POST"    => {["POST"], "form"},
      "COOKIES" => {nil, "cookie"},
      "META"    => {nil, "header"},
      "data"    => {["POST", "PUT", "PATCH"], "form"},
    }

    # Map request parameter types to HTTP methods
    REQUEST_PARAM_TYPE_MAP = {
      "query"  => nil,
      "form"   => ["GET", "POST", "PUT", "PATCH"],
      "cookie" => nil,
      "header" => nil,
    }

    def analyze
      endpoints = [] of Endpoint

      # Find root Django URL configurations
      root_django_urls_list = find_root_django_urls()
      root_django_urls_list.each do |root_django_urls|
        logger.debug "Found Django URL configurations in #{root_django_urls.filepath}"
        @django_base_path = root_django_urls.basepath
        extract_endpoints(root_django_urls).each do |endpoint|
          endpoints << endpoint
        end
      end

      # Find static files
      begin
        static_prefix = "#{@base_path}/static/"
        get_files_by_prefix(static_prefix).each do |file|
          relative_path = file.sub("#{@base_path}/static/", "")
          endpoints << Endpoint.new("/#{relative_path}", "GET")
        end
      rescue e
        logger.debug e
      end

      endpoints
    end

    # Find all root Django URLs
    def find_root_django_urls : Array(DjangoUrls)
      root_django_urls_list = [] of DjangoUrls
      channel = Channel(String).new
      search_dir = @base_path

      populate_channel_with_files(channel)

      WaitGroup.wait do |wg|
        @options["concurrency"].to_s.to_i.times do
          wg.spawn do
            loop do
              begin
                file = channel.receive?
                break if file.nil?
                next if File.directory?(file)
                next if file.includes?("/site-packages/")
                if file.ends_with? ".py"
                  content = File.read(file, encoding: "utf-8", invalid: :skip)
                  content.scan(REGEX_ROOT_URLCONF) do |match|
                    next if match.size != 2
                    dotted_as_urlconf = match[1].split(".")
                    relative_path = "#{dotted_as_urlconf.join("/")}.py"

                    Dir.glob("#{escape_glob_path(search_dir)}/**/#{relative_path}") do |filepath|
                      basepath = filepath.split("/")[..-(dotted_as_urlconf.size + 1)].join("/")
                      root_django_urls_list << DjangoUrls.new("", filepath, basepath)
                    end
                  end
                end
              rescue e : File::NotFoundError
                logger.debug "File not found: #{file}, error: #{e}"
              end
            end
          end
        end
      end

      root_django_urls_list.uniq
    end

    # Extract endpoints from a Django URL configuration file
    def extract_endpoints(django_urls : DjangoUrls) : Array(Endpoint)
      logger.debug "Extracting endpoints from #{django_urls.filepath}"
      endpoints = [] of Endpoint
      url_base_path = File.dirname(django_urls.filepath)
      @visited_url_paths[django_urls.filepath] = true

      file = File.open(django_urls.filepath, encoding: "utf-8", invalid: :skip)
      content = file.gets_to_end
      package_map = find_imported_modules(@django_base_path, url_base_path, content)

      # Temporary fix to parse only the string after "urlpatterns = ["
      keywords = ["urlpatterns", "=", "["]
      keywords.each do |keyword|
        if !content.includes? keyword
          return endpoints
        end

        content = content.split(keyword, 2)[1]
      end

      # TODO: Parse correct urlpatterns from variable concatenation case
      content.scan(REGEX_ROUTE_MAPPING) do |route_match|
        next if route_match.size != 3
        route = route_match[1]
        route = route.gsub(/^\^/, "").gsub(/\$$/, "")
        view = route_match[2].split(",")[0]
        url = "/#{django_urls.prefix}/#{route}".gsub(/\/+/, "/")
        new_django_urls = nil
        view.scan(REGEX_INCLUDE_URLS) do |include_pattern_match|
          # Detect new URL configurations
          next if include_pattern_match.size != 2
          new_route_path = "#{@django_base_path}/#{include_pattern_match[1].gsub(".", "/")}.py"

          if File.exists?(new_route_path)
            new_django_urls = DjangoUrls.new("#{django_urls.prefix}#{route}", new_route_path, django_urls.basepath)
            details = Details.new(PathInfo.new(new_route_path))
            unless @visited_url_paths.has_key? new_django_urls.filepath
              extract_endpoints(new_django_urls).each do |endpoint|
                endpoint.details = details
                endpoints << endpoint
              end
            end
          end
        end
        next if new_django_urls != nil

        details = Details.new(PathInfo.new(django_urls.filepath))
        if view == ""
          endpoints << Endpoint.new(url, "GET", details)
        else
          dotted_as_names_split = view.split(".")

          filepath = ""
          function_or_class_name = ""
          dotted_as_names_split.each_with_index do |name, index|
            if (package_map.has_key? name) && (index < dotted_as_names_split.size)
              filepath, package_type = package_map[name]
              function_or_class_name = name
              if package_type == PackageType::FILE && index + 1 < dotted_as_names_split.size
                function_or_class_name = dotted_as_names_split[index + 1]
              end

              break
            end
          end

          if filepath != "" && /^[a-zA-Z_][a-zA-Z0-9_]*$/.match(function_or_class_name)
            extract_endpoints_from_file(url, filepath, function_or_class_name).each do |endpoint|
              endpoint.details = details
              endpoints << endpoint
            end
          else
            # By default, Django allows requests with methods other than GET as well
            endpoints << Endpoint.new(url, "GET", details)
          end
        end
      end

      endpoints
    end

    # Extract endpoints from a given file
    def extract_endpoints_from_file(url : ::String, filepath : ::String, function_or_class_name : ::String)
      @logger.debug "Extracting endpoints from #{filepath}"

      endpoints = Array(Endpoint).new
      suspicious_http_methods = ["GET"]
      suspicious_params = Array(Param).new

      content = File.read(filepath, encoding: "utf-8", invalid: :skip)
      content_lines = content.split "\n"

      # Function Based View
      function_start_index = content.index /def\s+#{function_or_class_name}\s*\(/
      if !function_start_index.nil?
        function_codeblock = parse_code_block(content[function_start_index..])
        if !function_codeblock.nil?
          lines = function_codeblock.split "\n"
          function_define_line = lines[0]
          lines = lines[1..]

          # Check if the decorator line contains an HTTP method
          index = content_lines.index(function_define_line)
          if !index.nil?
            while index > 0
              index -= 1

              preceding_definition = content_lines[index]
              if preceding_definition.size > 0 && preceding_definition[0] == '@'
                HTTP_METHODS.each do |http_method_name|
                  method_name_match = preceding_definition.downcase.match /[^a-zA-Z0-9](#{http_method_name})[^a-zA-Z0-9]/
                  if !method_name_match.nil?
                    suspicious_http_methods << http_method_name.upcase
                  end
                end
              end

              break
            end
          end

          lines.each do |line|
            # Check if line has 'request.method == "GET"' similar pattern
            if line.includes? "request.method"
              suspicious_code = line.split("request.method")[1].strip
              HTTP_METHODS.each do |http_method_name|
                method_name_match = suspicious_code.downcase.match /['"](#{http_method_name})['"]/
                if !method_name_match.nil?
                  suspicious_http_methods << http_method_name.upcase
                end
              end
            end

            extract_params_from_line(line, suspicious_http_methods).each do |param|
              suspicious_params << param
            end
          end

          suspicious_http_methods.uniq.each do |http_method_name|
            endpoints << Endpoint.new(url, http_method_name, filter_params(http_method_name, suspicious_params))
          end

          return endpoints
        end
      end

      # Class Based View
      regext_http_methods = HTTP_METHODS.join "|"
      class_start_index = content.index /class\s+#{function_or_class_name}\s*[\(:]/
      if !class_start_index.nil?
        class_codeblock = parse_code_block(content[class_start_index..])
        if !class_codeblock.nil?
          lines = class_codeblock.split "\n"
          class_define_line = lines[0]
          lines = lines[1..]

          # Determine implicit HTTP methods based on class name
          if class_define_line.includes? "Form"
            suspicious_http_methods << "GET"
            suspicious_http_methods << "POST"
          elsif class_define_line.includes? "Delete"
            suspicious_http_methods << "DELETE"
            suspicious_http_methods << "POST"
          elsif class_define_line.includes? "Create"
            suspicious_http_methods << "POST"
          elsif class_define_line.includes? "Update"
            suspicious_http_methods << "POST"
          end

          # Check HTTP methods in class methods
          lines.each do |line|
            method_function_match = line.match(/\s+def\s+(#{regext_http_methods})\s*\(/)
            if !method_function_match.nil?
              suspicious_http_methods << method_function_match[1].upcase
            end

            extract_params_from_line(line, suspicious_http_methods).each do |param|
              suspicious_params << param
            end
          end

          suspicious_http_methods.uniq.each do |http_method_name|
            endpoints << Endpoint.new(url, http_method_name, filter_params(http_method_name, suspicious_params))
          end

          return endpoints
        end
      end

      # Default to GET method
      [Endpoint.new(url, "GET")]
    end

    # Extract parameters from a line of code
    def extract_params_from_line(line : ::String, endpoint_methods : Array(::String))
      suspicious_params = Array(Param).new

      if line.includes? "request."
        REQUEST_PARAM_FIELD_MAP.each do |field_name, tuple|
          field_methods, param_type = tuple
          matches = line.scan(/request\.#{field_name}\[[rf]?['"]([^'"]*)['"]\]/)
          if matches.size == 0
            matches = line.scan(/request\.#{field_name}\.get\([rf]?['"]([^'"]*)['"]/)
          end

          if matches.size != 0
            matches.each do |match|
              next if match.size != 2
              param_name = match[1]
              if field_name == "META"
                if param_name.starts_with? "HTTP_"
                  param_name = param_name[5..]
                end
              end

              # If a specific parameter is found, allow the corresponding methods
              if !field_methods.nil?
                field_methods.each do |field_method|
                  if !endpoint_methods.includes? field_method
                    endpoint_methods << field_method
                  end
                end
              end

              suspicious_params << Param.new(param_name, "", param_type)
            end
          end
        end
      end

      if line.includes? "form.cleaned_data"
        matches = line.scan(/form\.cleaned_data\[[rf]?['"]([^'"]*)['"]\]/)
        if matches.size == 0
          matches = line.scan(/form\.cleaned_data\.get\([rf]?['"]([^'"]*)['"]/)
        end

        if matches.size != 0
          matches.each do |match|
            next if match.size != 2
            suspicious_params << Param.new(match[1], "", "form")
          end
        end
      end

      suspicious_params
    end

    # Filter parameters based on HTTP method
    def filter_params(method : ::String, params : Array(Param))
      filtered_params = Array(Param).new
      upper_method = method.upcase

      params.each do |param|
        is_supported_param = false
        support_methods = REQUEST_PARAM_TYPE_MAP.fetch(param.param_type, nil)
        if !support_methods.nil?
          support_methods.each do |support_method|
            if upper_method == support_method.upcase
              is_supported_param = true
            end
          end
        else
          is_supported_param = true
        end

        filtered_params.each do |filtered_param|
          if filtered_param.name == param.name && filtered_param.param_type == param.param_type
            is_supported_param = false
            break
          end
        end

        if is_supported_param
          filtered_params << param
        end
      end

      filtered_params
    end

    module PackageType
      FILE = 0
      CODE = 1
    end

    struct DjangoUrls
      include JSON::Serializable
      property prefix, filepath, basepath

      def initialize(@prefix : ::String, @filepath : ::String, @basepath : ::String)
        if !File.directory? @basepath
          raise "The basepath for DjangoUrls (#{@basepath}) does not exist or is not a directory."
        end
      end
    end

    struct DjangoView
      include JSON::Serializable
      property prefix, filepath, name

      def initialize(@prefix : ::String, @filepath : ::String, @name : ::String)
        if !File.directory? @filepath
          raise "The filepath for DjangoView (#{@filepath}) does not exist."
        end
      end
    end
  end
end
