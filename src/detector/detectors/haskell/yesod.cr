require "../../../models/detector"

module Detector::Haskell
  class Yesod < Detector
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      if (base == "package.yaml" || filename.ends_with?(".cabal")) &&
         file_contents.match(/(^|[\s,])yesod(?:[-\w]*)?(?=$|[\s,<>=:])/)
        return true
      end

      return false unless filename.ends_with?(".hs") || filename.ends_with?(".lhs")

      return true if file_contents.includes?("import Yesod")
      return true if file_contents.includes?("import Yesod.Core")
      return true if file_contents.includes?("mkYesod")
      return true if file_contents.includes?("mkYesodData")
      return true if file_contents.includes?("parseRoutes")
      return true if file_contents.includes?("parseRoutesFile")

      false
    end

    def set_name
      @name = "haskell_yesod"
    end
  end
end
