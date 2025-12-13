require "../../../models/detector"

module Detector::Java
  class Play < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Detect Play Framework by routes file or Play imports in Java files
      if filename.ends_with?("routes") || filename.ends_with?("routes.conf")
        # Check for Play-style route definitions
        return true if file_contents =~ /^\s*(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+/m
      end

      if filename.ends_with?(".java")
        # Check for Play Framework imports
        return true if file_contents.includes?("play.mvc.Controller") ||
                       file_contents.includes?("play.mvc.Result") ||
                       file_contents.includes?("play.libs.Json") ||
                       file_contents.includes?("play.routing")
      end

      false
    end

    def set_name
      @name = "java_play"
    end
  end
end
