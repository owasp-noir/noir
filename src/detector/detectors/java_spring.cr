require "../../models/detector"

class DetectorJavaSpring < Detector
  def detect(filename : String, file_contents : String) : Bool
    if (filename.ends_with? "build.gradle") && (file_contents.includes? "org.springframework")
      return true
    elsif (filename.ends_with? "pom.xml") && (file_contents.includes? "org.springframework")
      return true
    end

    false
  end

  def set_name
    @name = "java_spring"
  end
end
