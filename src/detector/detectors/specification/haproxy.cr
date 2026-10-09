require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class Haproxy < Detector
    # Registers HAProxy configs (`*.cfg`, `haproxy*`) that match on the request
    # path in `CodeLocator`.
    detector_for "haproxy", idempotent: false

    # `frontend web` / `listen stats` / `backend api`. nginx's `listen 80;`
    # takes a port, not a name.
    SECTION = /^[ \t]*(?:frontend|backend|listen)[ \t]+[A-Za-z_]/m
    # A path fetch in an ACL definition or an anonymous `{ ... }` ACL.
    PATH_ACL = /(?:^[ \t]*acl[ \t]+\S+|\{)[ \t]+path(?:_beg|_end|_reg|_dir|_sub)?\b/m

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cfg") || File.basename(filename).starts_with?("haproxy")
    end

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      found = content_matches?(file_contents, SECTION) && content_matches?(file_contents, PATH_ACL)
      CodeLocator.instance.push(Noir::LocatorKeys::HAPROXY_SPEC, filename) if found
      found
    end
  end
end
