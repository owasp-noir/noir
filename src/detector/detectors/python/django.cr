require "../../../models/detector"

module Detector::Python
  class Django < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".py") && (file_contents.includes? "from django.")
        true
      else
        false
      end
    end

    def set_name
      @name = "python_django"
    end
  end
end
