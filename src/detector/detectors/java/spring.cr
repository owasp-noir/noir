require "../../../models/detector"

module Detector::Java
  class Spring < Detector
    detector_for "java_spring", extensions: %w[.java]

    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".java") && (file_contents.includes? "org.springframework")
        return true
      end

      false
    end
  end
end
