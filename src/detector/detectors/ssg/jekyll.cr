require "../../../models/detector"

class DetectorJekyll < Detector
  def detect(filename : String, file_contents : String) : Bool
    if (filename.includes? "Gemfile") && (file_contents.includes? "jekyll")
      true
    else
      false
    end
  end

  def set_name
    @name = "jekyll"
  end
end
