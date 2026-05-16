require "../../../models/detector"

module Detector::Lua
  class Lapis < Detector
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # `*.rockspec` (LuaRocks manifest) listing the `lapis` dependency.
      if filename.ends_with?(".rockspec") &&
         file_contents.match(/\blapis\b/) &&
         (file_contents.includes?("dependencies") || file_contents.includes?("dependency"))
        return true
      end

      # `config.lua` / `config.moon` carrying a Lapis config block.
      if (base == "config.lua" || base == "config.moon") &&
         file_contents.match(/\blapis\.(?:config|util|application)\b/)
        return true
      end

      return false unless filename.ends_with?(".lua") || filename.ends_with?(".moon")

      return true if file_contents.match(/require\s*\(?\s*['"]lapis(?:\.|['"])/)
      return true if file_contents.includes?("lapis.Application")
      return true if file_contents.match(/class\s+\w*\s*extends\s+lapis\.Application/)
      return true if file_contents.match(/extends\s+lapis\.Application/)

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".lua") || filename.ends_with?(".moon") || filename.ends_with?(".rockspec")
    end

    def set_name
      @name = "lua_lapis"
    end
  end
end
