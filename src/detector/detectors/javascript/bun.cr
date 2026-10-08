require "../../../models/detector"

module Detector::Javascript
  class Bun < Detector
    detector_for "js_bun", extensions: %w[.js .mjs .cjs .jsx .ts .mts .tsx]

    # `Bun.serve({ fetch: app.fetch })` only hosts a framework app (Hono,
    # Elysia); require a route map or request branching of its own.
    ROUTING_SIGNAL = /\b(?:routes|static)\s*[:,}]|\.\s*pathname\b|\bURLPattern\b|\.\s*method\b/

    def detect(filename : String, file_contents : String) : Bool
      file_contents.includes?("Bun.serve") && content_matches?(file_contents, ROUTING_SIGNAL)
    end
  end
end
