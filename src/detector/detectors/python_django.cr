require "../../models/detector"

class DetectorPythonDjango < Detector
  def detect(filename : String, file_contents : String) : Bool
    if (filename.includes? ".py") && (file_contents.includes? "from django.")
      true
    else
      false
    end
  end

  def set_name
    @name = "python_django"
  end
end
