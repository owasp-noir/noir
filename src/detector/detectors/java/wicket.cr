require "../../../models/detector"

module Detector::Java
  class Wicket < Detector
    detector_for "java_wicket"

    SOURCE_MARKERS = Regex.union("org.apache.wicket", "extends WebApplication", "@MountPath")
    BUILD_MARKERS  = Regex.union("org.apache.wicket", "wicket-core", "wicket-auth-roles", "wicketstuff")

    def detect(filename : String, file_contents : String) : Bool
      # `build_file?` never matches `.java`, so the source markers decide
      # the answer outright for those.
      return content_matches?(file_contents, SOURCE_MARKERS) if filename.ends_with?(".java")

      build_file?(filename) && content_matches?(file_contents, BUILD_MARKERS)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".java") || build_file?(filename)
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
