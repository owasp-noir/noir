require "../../../models/detector"

module Detector::Java
  class Struts2 < Detector
    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?(".java")
        return true if file_contents.includes?("org.apache.struts2")
        return true if file_contents.includes?("com.opensymphony.xwork2")
        return true if file_contents.includes?("@Action") && file_contents.includes?("@Namespace")
      end

      if filename.ends_with?(".xml")
        basename = File.basename(filename)
        return true if file_contents.includes?("org.apache.struts2.dispatcher")
        return true if file_contents.includes?("struts2-core") ||
                       file_contents.includes?("struts2-convention-plugin") ||
                       file_contents.includes?("struts2-rest-plugin")

        if basename == "struts.xml" || basename == "struts-plugin.xml" || basename == "struts-deferred.xml" || basename.ends_with?("-struts.xml")
          return true if file_contents.includes?("<struts") && file_contents.includes?("<package")
        end
      end

      if filename.ends_with?(".gradle") || filename.ends_with?(".gradle.kts") || filename.ends_with?(".properties")
        return true if file_contents.includes?("struts2-core") ||
                       file_contents.includes?("struts2-convention-plugin") ||
                       file_contents.includes?("struts2-rest-plugin")
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".java") ||
        filename.ends_with?(".xml") ||
        filename.ends_with?(".gradle") ||
        filename.ends_with?(".gradle.kts") ||
        filename.ends_with?(".properties")
    end

    def set_name
      @name = "java_struts2"
    end
  end
end
