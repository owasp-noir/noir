require "../../../models/detector"
require "../../../models/code_locator"
require "../../../miniparsers/thrift_idl"

module Detector::Specification
  class Thrift < Detector
    # Records every `.thrift` file that defines a service in `CodeLocator`
    # for the analyzer pass. Must keep running after the first match so all
    # service files get registered.
    detector_for "thrift", extensions: %w[.thrift], idempotent: false

    # A Thrift RPC surface is a `service Name [extends Base] {` block. The
    # bare word "service" also turns up in field names (`1: string service`)
    # and doc comments, so only the structural header counts, and only once
    # comments are blanked — a struct-only or commented-out file is not one.
    SERVICE_BLOCK = /\bservice\s+[A-Za-z_][\w.]*\s*(?:extends\s+[A-Za-z_][\w.]*\s*)?\{/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".thrift")
      return false unless content_matches?(file_contents, SERVICE_BLOCK)
      return false unless content_matches?(Noir::ThriftIdl.strip_comments(file_contents), SERVICE_BLOCK)

      CodeLocator.instance.push(Noir::LocatorKeys::THRIFT_IDL, filename)
      true
    end
  end
end
