require "../../../models/detector"
require "../../../utils/serverless_layout"

module Detector::Javascript
  # A Netlify Function: a handler module in the default
  # `netlify/functions/` (or `netlify/edge-functions/`) directory. Sites
  # that move the directory (`[functions] directory` in netlify.toml) are
  # picked up from the toml itself.
  class NetlifyFunctions < Detector
    detector_for "js_netlify_functions", path_sensitive: true

    EXTENSIONS = {".js", ".mjs", ".cjs", ".ts", ".mts", ".cts", ".jsx", ".tsx"}

    # `export default async (req, context) => ...`, `export default { fetch }`,
    # legacy `export const handler = ...` / `exports.handler = ...`.
    HANDLER_EXPORT = /(?:^|[^\w$.])export\s+default\b|(?:^|[^\w$.])export\s+(?:(?:async\s+)?function\s+|(?:const|let|var)\s+)handler\b|(?:^|[^\w$.])(?:module\s*\.\s*)?exports\s*\.\s*handler\s*=/m

    # `[functions] directory = "..."`, legacy `[build] functions = "..."` /
    # `edge_functions = "..."`.
    TOML_FUNCTIONS_DIR = /^\s*\[functions\]\s*(?:#[^\n]*)?\n(?:(?!\s*\[)[^\n]*\n)*?\s*directory\s*=/m
    TOML_BUILD_DIR     = /^\s*\[build\]\s*(?:#[^\n]*)?\n(?:(?!\s*\[)[^\n]*\n)*?\s*(?:edge_)?functions\s*=/m

    def applicable?(filename : String) : Bool
      return true if File.basename(filename) == "netlify.toml"
      return false unless EXTENSIONS.any? { |ext| filename.ends_with?(ext) }
      normalized = filename.gsub('\\', '/')
      normalized.includes?("netlify/functions/") || normalized.includes?("netlify/edge-functions/")
    end

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      if File.basename(filename) == "netlify.toml"
        return content_matches?(file_contents, TOML_FUNCTIONS_DIR) || content_matches?(file_contents, TOML_BUILD_DIR)
      end
      return false if Noir::ServerlessLayout.non_handler_file?(filename)

      relative = base_relative_path(filename).gsub('\\', '/')
      _, _, segments = Noir::ServerlessLayout.netlify_default_remainder(filename, relative) || return false
      return false if Noir::ServerlessLayout.netlify_function_name(segments).nil?
      content_matches?(file_contents, HANDLER_EXPORT)
    end
  end
end
