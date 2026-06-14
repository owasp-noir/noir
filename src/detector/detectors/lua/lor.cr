require "../../../models/detector"

module Detector::Lua
  class Lor < Detector
    def detect(filename : String, file_contents : String) : Bool
      # `*.rockspec` (LuaRocks manifest) declaring the `lor` dependency.
      if filename.ends_with?(".rockspec") &&
         file_contents.match(/['"]lor(?:\s|['"~<>=])/) &&
         (file_contents.includes?("dependencies") || file_contents.includes?("dependency"))
        return true
      end

      return false unless filename.ends_with?(".lua") || filename.ends_with?(".moon")

      # `require("lor.index")` / `require "lor.lib..."` — the framework import.
      return true if file_contents.match(/require\s*\(?\s*['"]lor(?:\.|['"])/)
      # `lor:Router()` router construction or `= lor()` app construction.
      return true if file_contents.match(/\blor\s*[:.]\s*[Rr]outer\s*\(/)
      return true if file_contents.match(/=\s*lor\s*\(\s*\)/)

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".lua") || filename.ends_with?(".moon") || filename.ends_with?(".rockspec")
    end

    def set_name
      @name = "lua_lor"
    end
  end
end
