require "../../../models/detector"

module Detector::Cpp
  class Crow < Detector
    CPP_EXTENSIONS = [".cpp", ".cc", ".cxx", ".h", ".hpp", ".hxx"]

    def detect(filename : String, file_contents : String) : Bool
      return false unless CPP_EXTENSIONS.any? { |ext| filename.ends_with?(ext) }

      return true if file_contents.includes?(%(#include "crow.h"))
      return true if file_contents.includes?("#include <crow.h>")
      return true if file_contents.includes?(%(#include "crow/crow.h"))
      return true if file_contents.includes?("#include <crow/crow.h>")
      return true if file_contents.includes?("#include <crow/app.h>")
      return true if file_contents.includes?(%(#include "crow/app.h"))
      return true if file_contents.includes?("crow::SimpleApp")
      return true if file_contents.includes?("CROW_ROUTE(")

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cpp") || filename.ends_with?(".cc") || filename.ends_with?(".cxx") || filename.ends_with?(".c") || filename.ends_with?(".h") || filename.ends_with?(".hpp") || filename.ends_with?(".hxx")
    end

    def set_name
      @name = "cpp_crow"
    end
  end
end
