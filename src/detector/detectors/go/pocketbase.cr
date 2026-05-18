require "../../../models/detector"

module Detector::Go
  class Pocketbase < Detector
    # Pocketbase apps are full Go programs that import the
    # framework's own `tools/router` package. The framework repo
    # itself self-references via the same path so the marker
    # works whether you're scanning a user app or the upstream.
    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("go.mod") && file_contents.includes?("github.com/pocketbase/pocketbase")
        true
      elsif filename.ends_with?(".go") && file_contents.includes?("pocketbase/tools/router")
        true
      else
        false
      end
    end

    def applicable?(filename : String) : Bool
      filename.includes?("go.mod") || filename.ends_with?(".go")
    end

    def set_name
      @name = "go_pocketbase"
    end
  end
end
