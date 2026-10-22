require "../../../models/detector"

module Detector::Java
  class Spark < Detector
    detector_for "java_spark", extensions: %w[.java]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      # `spark.Spark` must not be the tail of a longer package such as
      # `org.apache.spark.SparkConf` (Apache Spark, the data engine).
      file_contents.matches?(/(?<![\w.])spark\.Spark\b/) ||
        file_contents.includes?("import spark.") ||
        file_contents.includes?("import static spark.")
    end
  end
end
