require "./js_route_extractor"

module Noir
  # Firebase / Cloud Functions HTTPS functions declared with
  # `firebase-functions`: v1 `functions.https.onRequest(...)` /
  # `.onCall(...)` (optionally behind `.region(...)` / `.runWith(...)`) and
  # v2 `onRequest(...)` / `onCall(...)` from `firebase-functions/v2/https`.
  # The deployed function is named after its export, so the export name is
  # the route.
  module FirebaseFunctionsExtractor
    extend self

    # `kind` is the trigger: `onRequest`, `onCall` or `onCallGenkit`.
    # `args` is the call's argument text, handler included.
    record Trigger, name : String, kind : String, args : String, line : Int32

    # `exports.api =` / `module.exports.api =` / `export const api: T =`,
    # then a call chain ending in the trigger. Chain segments may carry one
    # level of nested parens: `.region(defineString("REGION"))`.
    EXPORT = /(?:\b(?:module\.)?exports\.([A-Za-z_$][\w$]*)|\bexport\s+(?:const|let|var)\s+([A-Za-z_$][\w$]*)(?:\s*:[^=;\n]+)?)\s*=\s*(?:[A-Za-z_$][\w$]*(?:\s*\([^()]*(?:\([^()]*\)[^()]*)*\))?\s*\.\s*)*(onRequest|onCall|onCallGenkit)\s*\(/

    def extract(content : String) : Array(Trigger)
      return [] of Trigger unless content.includes?("firebase-functions")

      code = JSRouteExtractor.strip_js_comments(content)
      triggers = [] of Trigger
      code.scan(EXPORT) do |m|
        open = m.end(0) - 1
        close = JSRouteExtractor.find_matching_paren(code, open) || next
        name = m[1]? || m[2]
        triggers << Trigger.new(name, m[3], code[(open + 1)...close], JSRouteExtractor.line_for_char_pos(code, m.begin(0)))
      end
      triggers
    end
  end
end
