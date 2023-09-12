require "../../models/detector"

class DetectorKotlinSpring < Detector
  def detect(filename : String, file_contents : String) : Bool
    if (filename.ends_with? "build.gradle.kts") && (file_contents.includes? "org.springframework")
      set_base_path true, get_parent_path(filename)

      true
    else
      false
    end
  end

  def set_name
    @name = "kotlin_spring"
  end
end
