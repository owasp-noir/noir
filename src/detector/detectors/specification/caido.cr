require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  class Caido < Detector
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
      content.includes?("\"host\"") &&
        content.includes?("\"method\"") &&
        content.includes?("\"path\"") &&
        content.includes?("\"raw\"") &&
        (content.includes?("\"is_tls\"") || content.includes?("\"port\""))
    end
  end
end
