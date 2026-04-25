require "../../../models/detector"

module Detector::Java
  class Spark < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      file_contents.includes?("spark.Spark") ||
        file_contents.includes?("import spark.") ||
        file_contents.includes?("import static spark.")
    end

    def set_name
      @name = "java_spark"
    end
  end
end
