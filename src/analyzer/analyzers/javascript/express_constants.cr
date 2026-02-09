module Analyzer::Javascript
  # Constants for Express router prefix tracking in CodeLocator
  module ExpressConstants
    # Base key prefix for router prefixes stored in CodeLocator
    # Format: "express_router_prefix:<file_path>" or "express_router_prefix:<file_path>:<function_name>"
    ROUTER_PREFIX_KEY = "express_router_prefix"

    # Common identifiers to skip when scanning for router variables
    SKIP_IDENTIFIERS = ["req", "res", "next", "err", "error", "true", "false", "null", "undefined"]

    # Common entry point filenames for Express applications
    ENTRY_FILENAMES = ["server.js", "app.js", "index.js", "main.js", "server.ts", "app.ts", "index.ts", "main.ts"]

    # Common subdirectories to check for entry points
    ENTRY_SUBDIRS = ["src", "lib", "app"]

    # JavaScript/TypeScript file extensions
    JS_EXTENSIONS = [".js", ".ts", ".jsx", ".tsx"]

    # Build a file-level key for CodeLocator
    def self.file_key(file_path : String) : String
      "#{ROUTER_PREFIX_KEY}:#{file_path}"
    end

    # Build a function-level key for CodeLocator
    def self.function_key(file_path : String, function_name : String) : String
      "#{ROUTER_PREFIX_KEY}:#{file_path}:#{function_name}"
    end
  end
end
