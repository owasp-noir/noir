require "../../../models/detector"

module Detector::Python
  class Robyn < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".py") && (file_contents.includes?("from robyn") || file_contents.includes?("import robyn"))
        true
      else
        false
      end
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".py")
    end

    def set_name
      @name = "python_robyn"
    end
  end
end
