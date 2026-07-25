require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  class Caido < Detector
    # Every `.json` in the tree reaches these guards. The first four must
    # all match, so they stay separate probes; only the last pair is an
    # alternation.
    HOST_MARKER        = /"host"/
    METHOD_MARKER      = /"method"/
    PATH_MARKER        = /"path"/
    RAW_MARKER         = /"raw"/
    TLS_OR_PORT_MARKER = Regex.union("\"is_tls\"", "\"port\"")

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".json")
      return false unless caido_json_candidate?(file_contents)

      begin
        data = JSON.parse(file_contents)
        array = data.as_a?
        return false unless array
        return false if array.empty?

        first = array.first.as_h?
        return false unless first

        # Caido's request-export shape: every entry carries the canonical
        # `host`/`method`/`path` triple plus the transport-level fields
        # (`is_tls`, `port`) and the base64-encoded `raw` message. Checking
        # all five together avoids collisions with HAR (top-level object,
        # not array), Postman (object with `info`/`item`), and Insomnia
        # (object with `_type: "export"`).
        return false unless first.has_key?("host") &&
                            first.has_key?("method") &&
                            first.has_key?("path") &&
                            first.has_key?("raw") &&
                            (first.has_key?("is_tls") || first.has_key?("port"))

        locator = CodeLocator.instance
        locator.push("caido-json", filename)
        true
      rescue
        false
      end
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".json")
    end

    def set_name
      @name = "caido"
    end

    # Registers Caido export paths in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def caido_json_candidate?(content : String) : Bool
      content_matches?(content, HOST_MARKER) &&
        content_matches?(content, METHOD_MARKER) &&
        content_matches?(content, PATH_MARKER) &&
        content_matches?(content, RAW_MARKER) &&
        content_matches?(content, TLS_OR_PORT_MARKER)
    end
  end
end
