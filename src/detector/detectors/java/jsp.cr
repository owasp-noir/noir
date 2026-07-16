require "../../../models/detector"

module Detector::Java
  class Jsp < Detector
    # Necessary-condition guard for the `.xml` branch: comment stripping
    # only removes text, so a marker absent from the raw content is also
    # absent from the stripped copy — the whole-file `gsub` allocation can
    # be skipped for the (overwhelmingly common) XML file without JSP
    # markers. (A marker split mid-token by an XML comment would defeat
    # this; no real deployment descriptor does that.)
    XML_MARKER = /<jsp-file>|JspServlet/

    def detect(filename : String, file_contents : String) : Bool
      # Any .jsp file is part of JSP attack surface
      return true if filename.ends_with?(".jsp")

      # Check Java files for JSP imports
      if filename.ends_with?(".java")
        return file_contents.includes?("javax.servlet.jsp") ||
          file_contents.includes?("jakarta.servlet.jsp") ||
          file_contents.includes?("@WebServlet") ||
          (file_contents.includes?("HttpServlet") && !!file_contents.match(/\bextends\s+HttpServlet\b/))
      end

      if filename.ends_with?(".xml")
        return false unless file_contents.matches?(XML_MARKER)
        xml_without_comments = file_contents.gsub(/<!--.*?-->/m, "")
        return xml_without_comments.includes?("<jsp-file>") ||
          !!xml_without_comments.match(/<servlet-class>\s*[^<]*\bJspServlet\b[^<]*<\/servlet-class>/)
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".jsp") || filename.ends_with?(".java") || filename.ends_with?(".xml")
    end

    def set_name
      @name = "java_jsp"
    end
  end
end
