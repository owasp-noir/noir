require "../../models/detector"

class DetectorExample < Detector
  def detect(filename : String, file_contents : String) : Bool
    false
  end

  def set_name
    @name = "example"
  end
end
