require "../../../models/detector"

module Detector::Go
  class Http < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".go")
      return false unless file_contents.includes?("net/http")
      # Trigger on net/http server usage while avoiding framework fixtures:
      # - Any "*NewServeMux" (covers http. and alias. forms) + net/http import is a strong
      #   signal of stdlib mux usage (frameworks use their own NewRouter etc).
      # - Direct "http.HandleFunc(" / "http.Handle(" for the default serve mux case
      #   (the "http." qualifier prevents catching r.HandleFunc in chi/mux/etc).
      file_contents.includes?("NewServeMux") ||
        file_contents.matches?(/http\.HandleFunc\s*\(/) ||
        file_contents.matches?(/http\.Handle\s*\(\s*["`\/]/)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".go") || filename.includes?("go.mod")
    end

    def set_name
      @name = "go_http"
    end
  end
end
