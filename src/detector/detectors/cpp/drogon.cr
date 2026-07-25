require "../../../models/detector"

module Detector::Cpp
  class Drogon < Detector
    detector_for "cpp_drogon", extensions: %w[.cpp .cc .cxx .c .h .hpp .hxx]

    DROGON_EXTENSIONS = [".cpp", ".cc", ".cxx", ".h", ".hpp"]

    def detect(filename : String, file_contents : String) : Bool
      return false unless DROGON_EXTENSIONS.any? { |ext| filename.ends_with?(ext) } ||
                          filename.includes?("CMakeLists.txt") ||
                          filename.includes?("conanfile") ||
                          filename.includes?("vcpkg.json")

      return true if file_contents.includes?("drogon/drogon.h")
      return true if file_contents.includes?("drogon/HttpController.h")
      return true if file_contents.includes?("drogon/HttpSimpleController.h")
      return true if file_contents.includes?("app().registerHandler")
      return true if file_contents.includes?("PATH_LIST_BEGIN")
      return true if file_contents.includes?("find_package(Drogon") || file_contents.includes?("find_package(drogon")

      false
    end
  end
end
