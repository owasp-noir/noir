require "../../../models/detector"

module Detector::Java
  class Spring < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".java") && (file_contents.includes? "org.springframework" || file_contents.includes?("org.springframework.cloud.openfeign.FeignClient"))
        return true
      end

      false
    end

    def set_name
      @name = "java_spring"
    end
  end
end
