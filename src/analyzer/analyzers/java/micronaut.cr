require "../../../models/analyzer"
require "../../../miniparsers/micronaut_extractor_ts"

module Analyzer::Java
  class Micronaut < Analyzer
    JAVA_EXTENSION    = "java"
    MICRONAUT_MARKERS = ["io.micronaut", "micronaut.io"]

    def analyze
      dto_builder = Noir::TreeSitterJavaDtoIndex.new

      file_list = all_files()
      file_list.each do |path|
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = File.read(path, encoding: "utf-8", invalid: :skip)
        next unless MICRONAUT_MARKERS.any? { |marker| content.includes?(marker) }

        package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name(content)
        next if package_name.empty?

        dto_index = dto_builder.build_for(path, content)

        Noir::TreeSitterMicronautExtractor.extract_routes(content, dto_index).each do |route|
          line = route.line + 1
          details = Details.new(PathInfo.new(path, line))
          @result << Endpoint.new(route.path, route.verb, route.params, details)
        end
      end

      Fiber.yield
      @result
    end
  end
end
