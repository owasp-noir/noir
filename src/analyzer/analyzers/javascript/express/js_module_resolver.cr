module Analyzer::Javascript
  # Resolves a JS/TS `require('./x')` / `import ... from './x'` specifier
  # to a file on disk.
  #
  # Extracted from `RouterMountScanner` so `RouteHelperScanner` resolves
  # specifiers identically: the mount pass decides which file a prefix
  # belongs to and the helper pass decides which file defines a helper, and
  # the two have to name the same file for a helper's routes to end up
  # under the right prefix.
  #
  # `root` anchors the `@/` and `~/` aliases — the scan base the importing
  # file belongs to. Bare specifiers (`express`, `@hapi/hapi`) resolve to
  # nil; a `node_modules` walk is deliberately out of scope.
  module JsModuleResolver
    # TypeScript ESM (`moduleResolution: NodeNext`) imports a sibling `.ts`
    # source through a `.js`-family specifier. Map each JS extension to the
    # TS source extension(s) it can stand in for.
    JS_TO_TS_EXT = {".js" => [".ts", ".tsx"], ".jsx" => [".tsx"], ".mjs" => [".mts"], ".cjs" => [".cts"]}

    def self.resolve(from_file : String, require_path : String, root : String) : String?
      is_relative = require_path.starts_with?(".")
      is_root_alias = require_path.starts_with?("@/") || require_path.starts_with?("~/")
      return unless is_relative || is_root_alias

      resolved = if is_root_alias
                   alias_path = require_path.starts_with?("@/") ? require_path.lchop("@/") : require_path.lchop("~/")
                   File.expand_path(alias_path, root)
                 else
                   base_dir = File.dirname(from_file)
                   File.expand_path(require_path, base_dir)
                 end

      # Case 1: The resolved path is a file that exists
      return resolved if File.file?(resolved)

      # Case 2: Try adding common JS/TS extensions.
      # Using `File.extname(require_path).empty?` is wrong because files
      # like `./auth.route` have `File.extname` = `.route`, which is not
      # empty but also not a runnable JS extension. That incorrectly
      # short-circuits the extension search and leaves common Express
      # naming idioms (`foo.route`, `bar.controller`, `baz.service`)
      # unresolvable. Instead, skip the extension search only when the
      # path already ends with a recognized JS/TS extension.
      known_js_exts = [".js", ".ts", ".jsx", ".tsx", ".mjs", ".cjs", ".mts", ".cts"]
      unless known_js_exts.any? { |ext| require_path.ends_with?(ext) }
        [".js", ".ts", ".jsx", ".tsx"].each do |ext|
          with_ext = "#{resolved}#{ext}"
          return with_ext if File.file?(with_ext)
        end
      end

      # Case 2b: TypeScript ESM extension rewrite. With tsconfig
      # `moduleResolution: NodeNext`, TS source imports its OWN sibling
      # `.ts` modules through a `.js` (or `.mjs`/`.cjs`/`.jsx`) specifier:
      #   import usersRouter from './controllers/users.js'  // file is users.ts
      # The literal `.js` path doesn't exist on disk, so Case 1 misses and
      # Case 2 is skipped (the specifier already ends in a known ext).
      # Without this, every cross-file router mount in a modern TS project
      # (directus mounts ~40 controllers this way) fails to resolve and the
      # sub-routes lose their mount prefix (`/me` instead of `/users/me`).
      # Swap the JS extension for its TS counterpart before giving up.
      JS_TO_TS_EXT.each do |js_ext, ts_exts|
        next unless require_path.ends_with?(js_ext)
        base = resolved[0...(resolved.size - js_ext.size)]
        ts_exts.each do |ts_ext|
          candidate = "#{base}#{ts_ext}"
          return candidate if File.file?(candidate)
        end
      end

      # Case 3: The path is a directory, look for an index file
      if File.directory?(resolved)
        ["index.js", "index.ts", "index.jsx", "index.tsx"].each do |index_file|
          index_path = File.join(resolved, index_file)
          return index_path if File.file?(index_path)
        end
      end

      nil
    end
  end
end
