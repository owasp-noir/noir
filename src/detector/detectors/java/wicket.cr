require "../../../models/detector"

module Detector::Java
  class Wicket < Detector
    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?(".java")
        return true if file_contents.includes?("org.apache.wicket")
        return true if file_contents.includes?("extends WebApplication")
        return true if file_contents.includes?("@MountPath")
      end

      build_file?(filename) && (
        file_contents.includes?("org.apache.wicket") ||
          file_contents.includes?("wicket-core") ||
          file_contents.includes?("wicket-auth-roles") ||
          file_contents.includes?("wicketstuff")
      )
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".java") || build_file?(filename)
    end

    def set_name
      @name = "java_wicket"
    end

    private def build_file?(filename : String) : Bool
      filename.ends_with?(".gradle") ||
        filename.ends_with?(".gradle.kts") ||
        filename.ends_with?(".xml") ||
        filename.ends_with?(".properties") ||
        filename.ends_with?(".yml") ||
        filename.ends_with?(".yaml")
    end
  end
end
