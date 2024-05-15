require "../../../models/detector"

class DetectorHugo < Detector
  def detect(filename : String, file_contents : String) : Bool
    if (filename.includes? "hugo.toml")
      if (file_contents.includes? "baseURL") || (file_contents.includes? "title")
        true
      else
        false
      end
    else
      false
    end
  end

  def set_name
    @name = "hugo"
  end
end

