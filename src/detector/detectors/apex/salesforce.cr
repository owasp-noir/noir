require "../../../models/detector"

module Detector::Apex
  class Salesforce < Detector
    detector_for "apex_salesforce", extensions: %w[.cls], basenames: %w[sfdx-project.json]

    # An Apex entry point. `.cls` is also a LaTeX class and a VB6 class
    # module; neither carries these next to an access-modified `class` line.
    ENTRY_RE = /@(?:RestResource|AuraEnabled)\b|\bwebservice\s+static\b|\bstatic\s+webservice\b/i
    CLASS_RE = /\b(?:public|global)\b[\w\s]*\bclass\s+\w+/i

    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?("sfdx-project.json")
        file_contents.includes?("packageDirectories")
      else
        content_matches?(file_contents, ENTRY_RE) && content_matches?(file_contents, CLASS_RE)
      end
    end
  end
end
