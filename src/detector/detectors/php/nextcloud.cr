require "../../../models/detector"

module Detector::Php
  # A Nextcloud app: `appinfo/info.xml` declaring a `<nextcloud>` dependency,
  # or PHP importing the app framework (`OCP\AppFramework\...`).
  class Nextcloud < Detector
    detector_for "php_nextcloud", extensions: %w[.php], basenames: %w[info.xml]

    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "info.xml"
        return filename.ends_with?("appinfo/info.xml") && file_contents.includes?("<nextcloud")
      end
      Noir::FileExtension.fold(filename).ends_with?(".php") && file_contents.includes?("OCP\\AppFramework\\")
    end
  end
end
