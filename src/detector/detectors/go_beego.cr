require "../../models/detector"

class DetectorGoBeego < Detector
  def detect(filename : String, file_contents : String) : Bool
    if (filename.includes? "go.mod") && (file_contents.includes? "github.com/beego/beego")
      true
    else
      false
    end
  end

  def set_name
    @name = "go_beego"
  end
end
