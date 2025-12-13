require "../../../models/detector"

module Detector::Scala
  class Play < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Detect Play Framework by Scala-specific indicators
      if filename.ends_with?(".scala")
        # Check for Play Framework imports
        return true if file_contents.includes?("play.api.mvc") ||
                       file_contents.includes?("play.api.routing") ||
                       file_contents.includes?("play.api.libs.json") ||
                       file_contents.includes?("BaseController") ||
                       file_contents.includes?("AbstractController")
      end

      # Check routes file only if there are Scala indicators nearby
      if filename.ends_with?("routes") || filename.ends_with?("routes.conf")
        # Check for Play-style route definitions with Scala-style types
        if file_contents =~ /^\s*(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+/m
          # Look for Scala-specific patterns in routes file (e.g., Option[...], ?=)
          return true if file_contents.includes?("Option[") || file_contents.includes?("?=")
        end
      end

      false
    end

    def set_name
      @name = "scala_play"
    end
  end
end
