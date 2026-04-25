require "../../../models/analyzer"
require "../../../miniparsers/jaxrs_extractor_ts"
require "../../../miniparsers/import_graph"

module Analyzer::Java
  class JaxRs < Analyzer
    JAVA_EXTENSION = "java"

    def analyze
      dto_builder = Noir::TreeSitterJavaDtoIndex.new
      bean_cache = Hash(String, Hash(String, Array(Param))).new

      file_list = all_files()
      file_list.each do |path|
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = File.read(path, encoding: "utf-8", invalid: :skip)

        # Cheap pre-filter: only files that mention JAX-RS bindings
        # carry resource classes. Avoids parsing the entire source
        # tree for unrelated `.java` files.
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

    # Build the cross-file `@BeanParam` index for `path`. Same
    # traversal as the DTO index — current file + same-package
    # siblings + imports — but each file's `extract_bean_fields`
    # result is memoised in the analyzer's per-run cache.
    private def bean_index_for(path : String,
                               content : String,
                               package_name : String,
                               cache : Hash(String, Hash(String, Array(Param)))) : Hash(String, Array(Param))
      result = Hash(String, Array(Param)).new
      imports = Noir::TreeSitterJavaParameterExtractor.extract_imports(content)

      Noir::ImportGraph.related_files(path, package_name, imports, JAVA_EXTENSION) do |file|
        beans = cache[file] ||= begin
          body = file == path ? content : File.read(file, encoding: "utf-8", invalid: :skip)
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
