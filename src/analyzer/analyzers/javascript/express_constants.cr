require "../../../models/analyzer"
require "../../../models/locator_keys"

module Analyzer::Javascript
  # Constants for Express router prefix tracking in CodeLocator
  module ExpressConstants
    # Common identifiers to skip when scanning for router variables
    SKIP_IDENTIFIERS = ["req", "res", "next", "err", "error", "true", "false", "null", "undefined"]

    # Common entry point filenames for Express applications
    ENTRY_FILENAMES = ["server.js", "app.js", "index.js", "main.js", "server.ts", "app.ts", "index.ts", "main.ts"]

    # Common subdirectories to check for entry points
    ENTRY_SUBDIRS = ["src", "lib", "app"]

    # JavaScript/TypeScript file extensions
    JS_EXTENSIONS = [".js", ".ts", ".jsx", ".tsx"]

    # File- and function-level keys for the router prefixes this analyzer
    # stashes in `CodeLocator`. The names are minted from the scanned path,
    # so they cannot be constants — they come from the declared
    # `EXPRESS_ROUTER_PREFIX` namespace instead, which is what puts them
    # under the same lifecycle and enforcement as every other slot.
    def self.file_key(file_path : String) : Noir::LocatorKey(Array(String))
      Noir::LocatorKeys::EXPRESS_ROUTER_PREFIX.key(file_path)
    end

    def self.function_key(file_path : String, function_name : String) : Noir::LocatorKey(Array(String))
      Noir::LocatorKeys::EXPRESS_ROUTER_PREFIX.key(file_path, function_name)
    end
  end
end
