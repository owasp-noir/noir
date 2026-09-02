require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class Oas3 < Detector
    # Registers every OAS3 spec path in `CodeLocator` for the
    # analyzer pass. Must keep running after first match.
    detector_for "oas3", extensions: %w[.json .yaml .yml], idempotent: false

    # Every `.json`/`.yaml`/`.yml` in the tree reaches this gate. A bare
    # `/openapi/` matched any document that merely *mentions* OpenAPI — an
    # `x-origin: {url: .../openapi.yaml}` block, a description, a `swagger`
    # document that links to its own OAS3 conversion — and each of those paid
    # for a full YAML/JSON parse before being rejected.
    #
    # In YAML a key at column 0 is a root key: a block scalar's content must be
    # indented past the key that introduces it, so an `openapi: 3.x` line
    # starting at column 0 cannot be anything but the document's version field.
    # That makes the anchored match as strong as the parse it replaces, so the
    # YAML branch registers on the regex alone and lets the analyzer — which
    # parses the document anyway — be the one that reads it. Previously every
    # OpenAPI document in the tree was parsed twice: once to decide, once to
    # analyze, with the first parse thrown away.
    OPENAPI3_YAML_MARKER = /^["']?openapi["']?[ \t]*:[ \t]*["']?3\./m

    # JSON gets no such structural guarantee — `"openapi": "3.0.0"` can sit
    # nested inside a wrapper document — so the JSON branch keeps parsing and
    # checking the root key, and the regex only serves as a cheap pre-gate.
    OPENAPI3_JSON_MARKER = /"openapi"[ \t]*:[ \t]*"3\./

    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?(".json")
        return false unless content_matches?(file_contents, OPENAPI3_JSON_MARKER)
        begin
          data = JSON.parse(file_contents)
          if data["openapi"].as_s.includes? "3."
            CodeLocator.instance.push(Noir::LocatorKeys::OAS3_JSON, filename)
            return true
          end
        rescue e
          logger.debug "OAS3 JSON detection failed for #{filename}: #{e}"
          record_unparsable_document(filename, e)
        end
      elsif filename.ends_with?(".yaml") || filename.ends_with?(".yml")
        if content_matches?(file_contents, OPENAPI3_YAML_MARKER)
          CodeLocator.instance.push(Noir::LocatorKeys::OAS3_YAML, filename)
          return true
        end
      end

      false
    end
  end
end
