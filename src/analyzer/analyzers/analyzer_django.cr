require "../../models/analyzer"
require "json"

class AnalyzerDjango < Analyzer
  REGEX_ROOT_URLCONF = /\s*ROOT_URLCONF\s*=\s*r?['"]([^'"\\]*)['"]/
  REGEX_URL_PATTERNS = /urlpatterns\s*=\s*\[(.*)\]/m
  REGEX_URL_MAPPING  = /[url|path|register]\s*\(\s*r?['"]([^'"\\]*)['"]\s*,\s*(.*)\s*\)/
  REGEX_INCLUDE_URLS = /include\s*\(\s*r?['"]([^'"\\]*)['"]/

  def analyze
    result = [] of Endpoint

    # Django urls
    root_django_urls_list = search_root_django_urls_list()
    root_django_urls_list.each do |root_django_urls|
      get_endpoints(root_django_urls).each do |endpoint|
        result << endpoint
      end
    end

    # Static files
    Dir.glob("#{@base_path}/static/**/*") do |file|
      next if File.directory?(file)
      relative_path = file.sub("#{@base_path}/static/", "")
      @result << Endpoint.new("#{@url}/#{relative_path}", "GET")
    end

    result
  end

  def search_root_django_urls_list : Array(DjangoUrls)
    root_django_urls_list = [] of DjangoUrls
    Dir.glob("#{base_path}/**/*") do |file|
      spawn do
        next if File.directory?(file)
        if file.ends_with? ".py"
          content = File.read(file, encoding: "utf-8", invalid: :skip)
          content.scan(REGEX_ROOT_URLCONF) do |match|
            next if match.size != 2
            filepath = "#{base_path}/#{match[1].gsub(".", "/")}.py"
            if File.exists? filepath
              root_django_urls_list << DjangoUrls.new("", filepath)
            end
          end
        end
      end
      Fiber.yield
    end

    root_django_urls_list.uniq
  end

  def get_endpoints(django_urls : DjangoUrls) : Array(Endpoint)
    endpoints = [] of Endpoint
    paths = get_paths(django_urls)
    paths.each do |path|
      path = path.gsub("//", "/")
      unless path.starts_with?("/")
        path = "/#{path}"
      end

      endpoints << Endpoint.new(path, "GET")
    end

    endpoints
  end

  def get_paths(django_urls : DjangoUrls)
    paths = [] of String
    content = File.read(django_urls.filepath, encoding: "utf-8", invalid: :skip)
    content.scan(REGEX_URL_PATTERNS) do |match|
      next if match.size != 2
      paths = mapping_to_path(match[1], django_urls.prefix)
    end

    paths
  end

  def mapping_to_path(content : String, prefix : String = "")
    paths = Array(String).new
    content.scan(REGEX_URL_MAPPING) do |match|
      next if match.size != 3
      path = match[1]
      view = match[2]

      filepath = nil
      view.scan(REGEX_INCLUDE_URLS) do |include_pattern_match|
        next if include_pattern_match.size != 2
        filepath = "#{base_path}/#{include_pattern_match[1].gsub(".", "/")}.py"

        if File.exists?(filepath)
          new_django_urls = DjangoUrls.new("#{prefix}#{path}", filepath)
          new_paths = get_paths(new_django_urls)
          new_paths.each do |new_path|
            paths << new_path
          end
        end
      end
      path = path.gsub(/ /, "")
      path = path.gsub(/^\^/, "")
      path = path.gsub(/\$$/, "")

      unless path.starts_with?("/")
        path = "/#{path}"
      end
      paths << path
    end

    paths
  end
end

def analyzer_django(options : Hash(Symbol, String))
  instance = AnalyzerDjango.new(options)
  instance.analyze
end

struct DjangoUrls
  include JSON::Serializable
  property prefix, filepath

  def initialize(@prefix : String, @filepath : String)
  end
end

struct DjangoView
  include JSON::Serializable
  property prefix, filepath, name

  def initialize(@prefix : String, @filepath : String, @name : String)
  end
end
