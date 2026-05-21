require "../../../models/detector"

module Detector::Scala
  class ZioHttp < Detector
    def detect(filename : String, file_contents : String) : Bool
      if (filename.ends_with? ".scala") && (
           file_contents.includes?("zio.http") ||
           file_contents.includes?("zhttp.http")
         )
        return true
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".scala") || filename.ends_with?(".sbt") || File.basename(filename) == "build.sbt"
    end

    def set_name
      @name = "scala_zio_http"
    end
  end
end
