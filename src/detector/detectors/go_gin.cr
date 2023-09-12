require "../../models/detector"

class DetectorGoGin < Detector
  def detect(filename : String, file_contents : String) : Bool
    if (filename.includes? "go.mod") && (file_contents.includes? "github.com/gin-gonic/gin")
      true
    else
      false
    end
  end

  def set_name
    @name = "go_gin"
  end
end
