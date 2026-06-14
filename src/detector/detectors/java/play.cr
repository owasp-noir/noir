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

      # Check routes file only with a Java-specific type marker. `Integer` is
      # Java-only (Scala routes use `Int`); `Boolean`/`Long` are shared with
      # Scala, so keying on them misclassifies a Scala Play app as Java and runs
      # a second analyzer over the same routes — lila's `Boolean` action params
      # produced a full set of duplicate, prefix-doubled `java_play` endpoints.
      if filename.ends_with?("routes") || filename.ends_with?("routes.conf")
        if file_contents =~ /^\s*(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+/m
          return true if file_contents.includes?("Integer")
        end
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".java") ||
        filename.ends_with?("routes") ||
        filename.ends_with?("routes.conf")
    end

    def set_name
      @name = "java_play"
    end
  end
end
