require "../../../models/detector"

module Detector::Haskell
  class Servant < Detector
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      if (base == "package.yaml" || filename.ends_with?(".cabal")) &&
         file_contents.match(/(^|[\s,])servant(?:-[A-Za-z0-9]+)*(?=$|[\s,<>=:])/)
        return true
      end

      return false unless filename.ends_with?(".hs") || filename.ends_with?(".lhs")

      return true if file_contents.match(/^\s*import\s+(qualified\s+)?Servant(\s|\.|$)/m)
      return true if file_contents.match(/:>\s*\(?\s*(Get|Post|Put|Delete|Patch|Head|Options|Verb)\b/)
      return true if file_contents.includes?(":<|>") && file_contents.includes?(":>")

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".hs") || filename.ends_with?(".cabal") || filename.ends_with?(".dhall") || File.basename(filename) == "stack.yaml" || File.basename(filename) == "package.yaml"
    end

    def set_name
      @name = "haskell_servant"
    end
  end
end
