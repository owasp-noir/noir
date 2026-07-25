require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class TypeSpec < Detector
    # Registers TypeSpec spec paths in `CodeLocator`.
    detector_for "typespec", extensions: %w[.tsp], idempotent: false

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".tsp")
      # `.tsp` is unambiguous on its own, but the issue spec also calls out a
      # `@typespec/...` import header — accept either to stay tolerant of
      # snippets that omit `import` (e.g. partials, generated fixtures).
      ok = file_contents.includes?("@typespec/") ||
           file_contents.includes?("@route") ||
           file_contents.includes?("@get") ||
           file_contents.includes?("@post") ||
           file_contents.includes?("@put") ||
           file_contents.includes?("@patch") ||
           file_contents.includes?("@delete")
      return false unless ok

      CodeLocator.instance.push("typespec-spec", filename)
      true
    end
  end
end
