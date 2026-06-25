require "../../../models/detector"

module Detector::Lua
  # Detects Lua command-line apps via the argparse library or explicit `arg`
  # indexing. Never gates on bare os.getenv (lapis/lor config).
  class Cli < Detector
    MARKERS = /\brequire\s*\(?\s*['"]argparse['"]|\bargparse\s*\(|\barg\s*\[\s*\d+\s*\]/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".lua")
      file_contents.matches?(MARKERS)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".lua")
    end

    def set_name
      @name = "lua_cli"
    end
  end
end
