require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/micronaut_extractor_ts"

module Analyzer::Java
  class Micronaut < Analyzer
    JAVA_EXTENSION    = "java"
    MICRONAUT_MARKERS = ["io.micronaut", "micronaut.io"]

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      dto_builder = Noir::TreeSitterJavaDtoIndex.new

      file_list = all_files()
      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = read_file_content(path)
        next unless MICRONAUT_MARKERS.any? { |marker| content.includes?(marker) }

        package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name(content)
        next if package_name.empty?

        dto_index = dto_builder.build_for(path, content)

        Noir::TreeSitterMicronautExtractor.extract_routes(content, dto_index, include_callees: include_callee).each do |route|
          line = route.line + 1
          details = Details.new(PathInfo.new(path, line))
          endpoint = Endpoint.new(route.path, route.verb, route.params, details)
          route.callees.each do |(name, callee_line)|
            endpoint.push_callee(Callee.new(name, path: path, line: callee_line))
          end
          @result << endpoint
        end
      end

      Fiber.yield
      @result
    end
  end
end
