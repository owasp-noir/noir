require "../../../models/detector"

module Detector::Java
  class Spark < Detector
    detector_for "java_spark", extensions: %w[.java]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      file_contents.includes?("spark.Spark") ||
        file_contents.includes?("import spark.") ||
        file_contents.includes?("import static spark.")
    end
  end
end
