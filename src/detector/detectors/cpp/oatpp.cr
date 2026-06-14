require "../../../models/detector"

module Detector::Cpp
  class Oatpp < Detector
    CPP_EXTENSIONS = [".cpp", ".cc", ".cxx", ".h", ".hpp", ".hxx"]

    def detect(filename : String, file_contents : String) : Bool
      return false unless CPP_EXTENSIONS.any? { |ext| filename.ends_with?(ext) }

      return true if file_contents.includes?("oatpp::web::server::api::ApiController")
      return true if file_contents.includes?("OATPP_CODEGEN_BEGIN(ApiController)")
      return true if file_contents.includes?("#include \"oatpp/")
      return true if file_contents.includes?("#include <oatpp/")

      false
    end

    def applicable?(filename : String) : Bool
      CPP_EXTENSIONS.any? { |ext| filename.ends_with?(ext) } || filename.ends_with?(".c")
    end

    def set_name
      @name = "cpp_oatpp"
    end
  end
end
