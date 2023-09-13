require "../../models/detector"

class DetectorJavaSpring < Detector
  def detect(filename : String, file_contents : String) : Bool
    if (
         (filename.includes? "pom.xml") || (filename.ends_with? "build.gradle")
       ) && (file_contents.includes? "org.springframework")
      true
    else
      false
    end
  end

  def set_name
    @name = "java_spring"
  end
end
