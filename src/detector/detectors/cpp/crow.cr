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

    def set_name
      @name = "cpp_crow"
    end
  end
end
