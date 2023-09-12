require "../../models/detector"

class DetectorGoEcho < Detector
  def detect(filename : String, file_contents : String) : Bool
    if (filename.includes? "go.mod") && (file_contents.includes? "github.com/labstack/echo")
      true
    else
      false
    end
  end

  def set_name
    @name = "go_echo"
  end
end
