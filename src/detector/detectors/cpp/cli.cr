require "../../../models/detector"

module Detector::Cpp
  # Detects C++ command-line applications, gated on a CLI library / parser
  # construct (CLI11, getopt/getopt_long, cxxopts, boost::program_options,
  # gflags) — not on bare `main(int argc, char** argv)`, which every C++
  # program (servers included) has.
  class Cli < Detector
    EXTS     = [".cpp", ".cc", ".cxx", ".c++", ".hpp", ".hh", ".hxx"]
    CLI11    = /\bCLI::App\b|include\s*[<"]CLI\/CLI\.hpp/
    GETOPT   = /\bgetopt(?:_long)?\s*\(|\bstruct\s+option\b/
    CXXOPTS  = /\bcxxopts::/
    BOOST_PO = /\bprogram_options\b/
    GFLAGS   = /\bDEFINE_(?:string|int32|int64|bool|double|uint32|uint64)\s*\(/

    def detect(filename : String, file_contents : String) : Bool
      return false unless EXTS.any? { |ext| filename.ends_with?(ext) }
      file_contents.matches?(CLI11) || file_contents.matches?(GETOPT) ||
        file_contents.matches?(CXXOPTS) || file_contents.matches?(BOOST_PO) ||
        file_contents.matches?(GFLAGS)
    end

    def applicable?(filename : String) : Bool
      EXTS.any? { |ext| filename.ends_with?(ext) }
    end

    def set_name
      @name = "cpp_cli"
    end
  end
end
