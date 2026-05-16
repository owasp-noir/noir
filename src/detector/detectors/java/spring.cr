require "../../../models/detector"

module Detector::Java
  class Spring < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".java") && (file_contents.includes? "org.springframework")
        return true
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".java") || filename.ends_with?(".gradle") || filename.ends_with?(".gradle.kts") || filename.ends_with?(".xml") || filename.ends_with?(".properties") || filename.ends_with?(".yml") || filename.ends_with?(".yaml")
    end

    def set_name
      @name = "java_spring"
    end
  end
end
