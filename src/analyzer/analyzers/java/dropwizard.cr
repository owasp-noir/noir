require "../../../models/analyzer"
require "../../../miniparsers/jaxrs_extractor_ts"
require "../../../miniparsers/import_graph"

module Analyzer::Java
  # Dropwizard ships Jersey under the hood, so JAX-RS resource
  # classes are the routing surface. This analyzer drives the shared
  # `TreeSitterJaxRsExtractor` against files carrying the
  # `io.dropwizard` marker; the JAX-RS analyzer skips those files
  # so a Dropwizard project reports as just `java_dropwizard`.
  class Dropwizard < Analyzer
    JAVA_EXTENSION    = "java"
    DROPWIZARD_MARKER = "io.dropwizard"

    def analyze
      dto_builder = Noir::TreeSitterJavaDtoIndex.new
      bean_cache = Hash(String, Hash(String, Array(Param))).new

      file_list = all_files()
      file_list.each do |path|
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = read_file_content(path)
        next unless content.includes?(DROPWIZARD_MARKER)

        # Some Dropwizard files (Application, Module classes) won't
        # carry JAX-RS routes — skip the parse cost when the file
        # has no `jakarta/javax.ws.rs` reference at all.
        next unless content.includes?("jakarta.ws.rs") || content.includes?("javax.ws.rs")

        package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name(content)
        next if package_name.empty?

        dto_index = dto_builder.build_for(path, content)
        bean_index = bean_index_for(path, content, package_name, bean_cache)

        Noir::TreeSitterJaxRsExtractor.extract_routes(content, dto_index, bean_index).each do |route|
          line = route.line + 1
          details = Details.new(PathInfo.new(path, line))
          @result << Endpoint.new(route.path, route.verb, route.params, details)
        end
      end

      Fiber.yield
      @result
    end

    private def bean_index_for(path : String,
                               content : String,
                               package_name : String,
                               cache : Hash(String, Hash(String, Array(Param)))) : Hash(String, Array(Param))
      result = Hash(String, Array(Param)).new
      imports = Noir::TreeSitterJavaParameterExtractor.extract_imports(content)

      Noir::ImportGraph.related_files(path, package_name, imports, JAVA_EXTENSION) do |file|
        beans = cache[file] ||= begin
          body = file == path ? content : read_file_content(file)
          Noir::TreeSitterJaxRsExtractor.extract_bean_fields(body)
        rescue File::NotFoundError
          {} of String => Array(Param)
        end

        beans.each { |name, params| result[name] ||= params }
      end

      result
    end
  end
end
