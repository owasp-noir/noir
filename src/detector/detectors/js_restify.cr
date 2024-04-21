require "../../models/detector"

class DetectorJsRestify < Detector
  def detect(filename : String, file_contents : String) : Bool
    if (filename.includes? ".js") && (file_contents.includes? "require('restify')")
      true
    elsif (filename.includes? ".js") && (file_contents.includes? "require(\"restify\")")
      true
    elsif (filename.includes? ".ts") && (file_contents.includes? "server")
      true
    elsif (filename.includes? ".ts") && (file_contents.includes? "require(\"restify\")")
      true
    else
      false
    end
  end

  def set_name
    @name = "js_restify"
  end
end
