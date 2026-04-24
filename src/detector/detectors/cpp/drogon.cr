require "../../../models/detector"

module Detector::Cpp
  class Drogon < Detector
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

    def set_name
      @name = "cpp_drogon"
    end
  end
end
