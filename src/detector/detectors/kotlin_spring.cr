require "../../models/detector"

class DetectorKotlinSpring < Detector
  def detect(filename : String, file_contents : String) : Bool
    if (filename.ends_with? ".kt") && (file_contents.includes? "org.springframework")
      return true
    end

    false
  end

  def set_name
    @name = "kotlin_spring"
  end
end
