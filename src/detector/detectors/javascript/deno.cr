require "../../../models/detector"

module Detector::Javascript
  class Deno < Detector
    detector_for "js_deno", extensions: %w[.js .mjs .cjs .jsx .ts .mts .tsx]

    # `Deno.serve(app.fetch)` only hosts a framework app (Hono, Oak); require
    # request branching of its own.
    ROUTING_SIGNAL = /\.\s*pathname\b|\bURLPattern\b|\.\s*method\b/

    def detect(filename : String, file_contents : String) : Bool
      file_contents.includes?("Deno.serve") && content_matches?(file_contents, ROUTING_SIGNAL)
    end
  end
end
