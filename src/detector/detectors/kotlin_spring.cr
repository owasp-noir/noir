require "../../models/detector"

class DetectorKotlinSpring < Detector
  def detect(filename : String, file_contents : String) : Bool
    if (filename.ends_with? "build.gradle.kts") && (file_contents.includes? "org.springframework")
      return true
    elsif (filename.ends_with? "pom.xml") && (file_contents.includes? "org.springframework") && (file_contents.includes? "org.jetbrains.kotlin")
      return true
    end

    false
  end

  def set_name
    @name = "kotlin_spring"
  end
end
