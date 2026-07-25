require "../../../models/detector"

module Detector::Cpp
  # Detects C++ command-line applications, gated on a CLI library / parser
  # construct (CLI11, getopt/getopt_long, cxxopts, boost::program_options,
  # gflags, Abseil Flags, p-ranav/argparse) — not on bare
  # `main(int argc, char** argv)`, which every C++ program (servers
  # included) has.
  class Cli < Detector
    detector_for "cpp_cli"

    EXTS      = [".cpp", ".cc", ".cxx", ".c++", ".hpp", ".hh", ".hxx"]
    CLI11     = /\bCLI::App\b|include\s*[<"]CLI\/CLI\.hpp/
    GETOPT    = /\bgetopt(?:_long)?\s*\(|\bstruct\s+option\b/
    CXXOPTS   = /\bcxxopts::/
    BOOST_PO  = /\bprogram_options\b/
    GFLAGS    = /\bDEFINE_(?:string|int32|int64|bool|double|uint32|uint64)\s*\(/
    ABSL_FLAG = /\bABSL_FLAG\s*\(/
    ARGPARSE  = /\bargparse::ArgumentParser\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless EXTS.any? { |ext| filename.ends_with?(ext) }
      content_matches?(file_contents, CLI11) || content_matches?(file_contents, GETOPT) ||
        content_matches?(file_contents, CXXOPTS) || content_matches?(file_contents, BOOST_PO) ||
        content_matches?(file_contents, GFLAGS) || content_matches?(file_contents, ABSL_FLAG) ||
        content_matches?(file_contents, ARGPARSE)
    end

    def applicable?(filename : String) : Bool
      EXTS.any? { |ext| filename.ends_with?(ext) }
    end
  end
end
