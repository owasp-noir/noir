require "../../models/detector"

class DetectorGoFiber < Detector
  def detect(filename : String, file_contents : String) : Bool
    if (filename.includes? "go.mod") && (file_contents.includes? "github.com/gofiber/fiber")
      true
    else
      false
    end
  end

  def set_name
    @name = "go_fiber"
  end
end
