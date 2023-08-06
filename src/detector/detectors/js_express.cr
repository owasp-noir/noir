require "../../models/detector"

class DetectorJsExpress < Detector
  def detect(filename : String, file_contents : String) : Bool
    if (filename.includes? ".js") && (file_contents.includes? "require('express')")
      true
    elsif (filename.includes? ".js") && (file_contents.includes? "require(\"express\")")
      true
    else
      false
    end
  end

  def set_name
    @name = "js_express"
  end
end
