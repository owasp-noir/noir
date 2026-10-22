require "../../../models/detector"

module Detector::Cpp
  class Httplib < Detector
    detector_for "cpp_httplib", extensions: %w[.cpp .cc .cxx .h .hpp .hxx]

    CPP_EXTENSIONS = [".cpp", ".cc", ".cxx", ".h", ".hpp", ".hxx"]

    def detect(filename : String, file_contents : String) : Bool
      return false unless CPP_EXTENSIONS.any? { |ext| filename.ends_with?(ext) }

      # The single-header library may be included from any path
      # (`<httplib.h>`, `"httplib.hpp"`, `<vendor/httplib.h>`, …).
      return true if file_contents.includes?("httplib.h")
      return true if file_contents.includes?("httplib.hpp")
      # Qualified usage, or the `using namespace httplib` shorthand many apps use.
      return true if file_contents.includes?("httplib::")
      return true if file_contents.includes?("using namespace httplib")

      false
    end
  end
end
