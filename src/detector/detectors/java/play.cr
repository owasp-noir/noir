require "../../../models/detector"

module Detector::Java
  class Play < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Detect Play Framework by Java-specific indicators
      if filename.ends_with?(".java")
        # Check for Play Framework imports
        return true if file_contents.includes?("play.mvc.Controller") ||
                       file_contents.includes?("play.mvc.Result") ||
                       file_contents.includes?("play.libs.Json") ||
                       file_contents.includes?("play.routing")
      end

      # Check routes file only if there are Java indicators nearby
      if filename.ends_with?("routes") || filename.ends_with?("routes.conf")
        # Check for Play-style route definitions with Java-style types
        if file_contents =~ /^\s*(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+/m
          # Look for Java-specific patterns in routes file (e.g., Integer instead of Int)
          return true if file_contents.includes?("Integer") || file_contents.includes?("Boolean")
        end
      end

      false
    end

    def set_name
      @name = "java_play"
    end
  end
end
