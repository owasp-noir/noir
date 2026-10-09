require "../../../models/detector"
require "../../../miniparsers/camel_route_extractor"

module Detector::Java
  class Camel < Detector
    detector_for "java_camel", extensions: %w[.java .xml .yaml .yml .gradle .gradle.kts]

    def detect(filename : String, file_contents : String) : Bool
      case File.extname(filename)
      when ".java", ".gradle", ".kts"
        file_contents.includes?(Noir::CamelRouteExtractor::JAVA_DSL)
      when ".xml"
        File.basename(filename) == "pom.xml" ? file_contents.includes?("<groupId>org.apache.camel") : file_contents.matches?(Noir::CamelRouteExtractor::XML_DSL)
      else
        file_contents.matches?(Noir::CamelRouteExtractor::YAML_DSL)
      end
    end
  end
end
