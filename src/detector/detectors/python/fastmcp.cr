require "../../../models/detector"

module Detector::Python
  class FastMCP < Detector
    detector_for "python_fastmcp", extensions: %w[.py]

    # The `fastmcp` package and the official MCP SDK's `mcp.server.fastmcp`.
    IMPORT_RE = /^\s*(?:from\s+(?:fastmcp|mcp\.server\.fastmcp)(?:\.[\w.]+)?\s+import\b|import\s+fastmcp\b)/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py") && file_contents.includes?("fastmcp")
      file_contents.matches?(IMPORT_RE)
    end
  end
end
