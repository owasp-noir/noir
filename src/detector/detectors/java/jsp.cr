require "../../../models/detector"

module Detector::Java
  class Jsp < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Any .jsp file is part of JSP attack surface
      return true if filename.ends_with?(".jsp")

      # Check Java files for JSP imports
      if filename.ends_with?(".java")
        return file_contents.includes?("javax.servlet.jsp") ||
          file_contents.includes?("jakarta.servlet.jsp")
      end

      if filename.ends_with?(".xml")
        xml_without_comments = file_contents.gsub(/<!--.*?-->/m, "")
        return xml_without_comments.includes?("<jsp-file>") ||
          !!xml_without_comments.match(/<servlet-class>\s*[^<]*\bJspServlet\b[^<]*<\/servlet-class>/)
      end

      false
    end

    def set_name
      @name = "java_jsp"
    end
  end
end
