require "../../models/analyzer"
require "./analyzer_python"
require "json"

class AnalyzerDjango < AnalyzerPython
  @django_base_path : String = ""
  REGEX_ROOT_URLCONF      = /\s*ROOT_URLCONF\s*=\s*r?['"]([^'"\\]*)['"]/
  REGEX_ROUTE_MAPPING     = /(?:url|path|register)\s*\(\s*r?['"]([^"']*)['"][^,]*,\s*([^),]*)/
  REGEX_INCLUDE_URLS      = /include\s*\(\s*r?['"]([^'"\\]*)['"]/
  REQUEST_PARAM_FIELD_MAP = {
    "GET"     => {["GET"], "query"},
    "POST"    => {["POST"], "form"},
    "COOKIES" => {nil, "cookie"},
    "META"    => {nil, "header"},
    "data"    => {["POST", "PUT", "PATCH"], "form"},
  }
  REQUEST_PARAM_TYPE_MAP = {
    "query"  => nil,
    "form"   => ["GET", "POST", "PUT", "PATCH"],
    "cookie" => nil,
    "header" => nil,
  }

  def analyze
    result = [] of Endpoint

    # Django urls
    root_django_urls_list = search_root_django_urls_list()
    root_django_urls_list.each do |root_django_urls|
      @django_base_path = root_django_urls.basepath
      get_endpoints(root_django_urls).each do |endpoint|
        result << endpoint
      end
    end

    # Static files
    begin
      Dir.glob("#{@base_path}/static/**/*") do |file|
        next if File.directory?(file)
        relative_path = file.sub("#{@base_path}/static/", "")
        @result << Endpoint.new("#{@url}/#{relative_path}", "GET")
      end
    rescue e
      logger.debug e
    end

    result
  end

  def search_root_django_urls_list : Array(DjangoUrls)
    root_django_urls_list = [] of DjangoUrls

    search_dir = @base_path
    begin
      Dir.glob("#{search_dir}/**/*") do |file|
        spawn do
          begin
            next if File.directory?(file)
            if file.ends_with? ".py"
              content = File.read(file, encoding: "utf-8", invalid: :skip)
              content.scan(REGEX_ROOT_URLCONF) do |match|
                next if match.size != 2
                dotted_as_urlconf = match[1].split(".")
                relative_path = "#{dotted_as_urlconf.join("/")}.py"

                Dir.glob("#{search_dir}/**/#{relative_path}") do |filepath|
                  basepath = filepath.split("/")[..-(dotted_as_urlconf.size + 1)].join("/")
                  root_django_urls_list << DjangoUrls.new("", filepath, basepath)
                end
              end
            end
          rescue e : File::NotFoundError
            @logger.debug "File not found: #{file}"
          end
        end
        Fiber.yield
      end
    rescue e
      logger.debug e
    end

    root_django_urls_list.uniq
  end

  module PackageType
    FILE = 0
    CODE = 1
  end

  def get_endpoints(django_urls : DjangoUrls) : Array(Endpoint)
    endpoints = [] of Endpoint
    url_base_path = File.dirname(django_urls.filepath)

    file = File.open(django_urls.filepath, encoding: "utf-8", invalid: :skip)
    content = file.gets_to_end
    package_map = find_imported_modules(@django_base_path, url_base_path, content)

    # [Temporary Fix] Parse only the string after "urlpatterns = ["
    keywords = ["urlpatterns", "=", "["]
    keywords.each do |keyword|
      if !content.includes? keyword
        return endpoints
      end

      content = content.split(keyword, 2)[1]
    end

    # [TODO] Parse correct urlpatterns from variable concatenation case"
    content.scan(REGEX_ROUTE_MAPPING) do |route_match|
      next if route_match.size != 3
      route = route_match[1]
      route = route.gsub(/^\^/, "").gsub(/\$$/, "")
      view = route_match[2].split(",")[0]
      url = "/#{@url}/#{django_urls.prefix}/#{route}".gsub(/\/+/, "/")

      new_django_urls = nil
      view.scan(REGEX_INCLUDE_URLS) do |include_pattern_match|
        # Detect new url configs
        next if include_pattern_match.size != 2
        new_route_path = "#{@django_base_path}/#{include_pattern_match[1].gsub(".", "/")}.py"

        if File.exists?(new_route_path)
          new_django_urls = DjangoUrls.new("#{django_urls.prefix}#{route}", new_route_path, django_urls.basepath)
          get_endpoints(new_django_urls).each do |endpoint|
            endpoints << endpoint
          end
        end
      end
      next if new_django_urls != nil

      if view == ""
        endpoints << Endpoint.new(url, "GET")
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

        if filepath != ""
          get_endpoint_from_files(url, filepath, function_or_class_name).each do |endpoint|
            endpoints << endpoint
          end
        else
          # By default, Django allows requests with methods other than GET as well
          # Prevent this flow, we need to improve trace code of 'get_endpoint_from_files()
          endpoints << Endpoint.new(url, "GET")
        end
      end
    end

    endpoints
  end

  def get_endpoint_from_files(url : String, filepath : String, function_or_class_name : String)
    endpoints = Array(Endpoint).new
    suspicious_http_methods = ["GET"]
    suspicious_params = Array(Param).new

    content = File.read(filepath, encoding: "utf-8", invalid: :skip)
    content_lines = content.split "\n"

    # Function Based View
    function_start_index = content.index /def\s+#{function_or_class_name}\s*\(/
    if !function_start_index.nil?
      function_codeblock = parse_function_or_class(content[function_start_index..])
      if !function_codeblock.nil?
        lines = function_codeblock.split "\n"
        function_define_line = lines[0]
        lines = lines[1..]

        # Verify if the decorator line contains an HTTP method, for instance:
        # '@api_view(['POST'])', '@require_POST', '@require_http_methods(["GET", "POST"])'
        index = content_lines.index(function_define_line)
        if !index.nil?
          while index > 0
            index -= 1

            preceding_definition = content_lines[index]
            if preceding_definition.size > 0 && preceding_definition[0] == '@'
              HTTP_METHOD_NAMES.each do |http_method_name|
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
            HTTP_METHOD_NAMES.each do |http_method_name|
              method_name_match = suspicious_code.downcase.match /['"](#{http_method_name})['"]/
              if !method_name_match.nil?
                suspicious_http_methods << http_method_name.upcase
              end
            end
          end

          parse_params_in_codeline(line, suspicious_http_methods).each do |param|
            suspicious_params << param
          end
        end

        suspicious_http_methods.uniq.each do |http_method_name|
          endpoints << Endpoint.new(url, http_method_name, get_filtered_params(http_method_name, suspicious_params))
        end

        return endpoints
      end
    end

    # Class Based View
    regex_http_method_names = HTTP_METHOD_NAMES.join "|"
    class_start_index = content.index /class\s+#{function_or_class_name}\s*[\(:]/
    if !class_start_index.nil?
      class_codeblock = parse_function_or_class(content[class_start_index..])
      if !class_codeblock.nil?
        lines = class_codeblock.split "\n"
        class_define_line = lines[0]
        lines = lines[1..]

        # [TODO] Create a graph and use Django internal views
        # Suspicious implicit class name for this class
        # https://github.com/django/django/blob/main/django/views/generic/edit.py
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

        # Check http methods (django.views.View)
        lines.each do |line|
          method_function_match = line.match(/\s+def\s+(#{regex_http_method_names})\s*\(/)
          if !method_function_match.nil?
            suspicious_http_methods << method_function_match[1].upcase
          end

          parse_params_in_codeline(line, suspicious_http_methods).each do |param|
            suspicious_params << param
          end
        end

        suspicious_http_methods.uniq.each do |http_method_name|
          endpoints << Endpoint.new(url, http_method_name, get_filtered_params(http_method_name, suspicious_params))
        end

        return endpoints
      end
    end

    # GET is default http method
    [Endpoint.new(url, "GET")]
  end

  def parse_params_in_codeline(line : String, endpoint_methods : Array(String))
    suspicious_params = Array(Param).new

    if line.includes? "request."
      REQUEST_PARAM_FIELD_MAP.each do |field_name, tuple|
        field_methods, noir_param_type = tuple
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

            # If it receives a specific parameter, it is considered to allow the method.
            if !field_methods.nil?
              field_methods.each do |field_method|
                if !endpoint_methods.includes? field_method
                  endpoint_methods << field_method
                end
              end
            end

            suspicious_params << Param.new(param_name, "", noir_param_type)
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

  def get_filtered_params(method : String, params : Array(Param))
    filtered_params = Array(Param).new
    upper_method = method.upcase

    params.each do |param|
      is_support_param = false
      support_methods = REQUEST_PARAM_TYPE_MAP.fetch(param.param_type, nil)
      if !support_methods.nil?
        support_methods.each do |support_method|
          if upper_method == support_method.upcase
            is_support_param = true
          end
        end
      else
        is_support_param = true
      end

      filtered_params.each do |filtered_param|
        if filtered_param.name == param.name && filtered_param.param_type == param.param_type
          is_support_param = false
          break
        end
      end

      if is_support_param
        filtered_params << param
      end
    end

    filtered_params
  end
end

def analyzer_django(options : Hash(Symbol, String))
  instance = AnalyzerDjango.new(options)
  instance.analyze
end

struct DjangoUrls
  include JSON::Serializable
  property prefix, filepath, basepath

  def initialize(@prefix : String, @filepath : String, @basepath : String)
    if !File.directory? @basepath
      raise "The basepath for DjangoUrls (#{@basepath}) does not exist or is not a directory."
    end
  end
end

struct DjangoView
  include JSON::Serializable
  property prefix, filepath, name

  def initialize(@prefix : String, @filepath : String, @name : String)
    if !File.directory? @filepath
      raise "The filepath for DjangoView (#{@filepath}) does not exist."
    end
  end
end
