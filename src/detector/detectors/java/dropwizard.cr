require "../../../models/detector"

module Detector::Java
  class Dropwizard < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      file_contents.includes?("io.dropwizard")
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".java") || filename.ends_with?(".gradle") || filename.ends_with?(".gradle.kts") || filename.ends_with?(".xml") || filename.ends_with?(".properties") || filename.ends_with?(".yml") || filename.ends_with?(".yaml")
    end

    def set_name
      @name = "java_dropwizard"
    end
  end
end
