require "../../../../models/code_locator"
require "../../../../utils/js_literal_scanner"
require "../../../../utils/url_path"
require "../express_constants"

module Analyzer::Javascript
  # RouterMountScanner handles the two-pass scanning process for Express router mounts.
  # It scans JavaScript/TypeScript files to discover router mount patterns like:
  #   app.use('/api', userRouter)
  #   router.use('/v1', require('./routes'))
  # and stores the prefix information in CodeLocator for cross-file resolution.
  class RouterMountScanner
    include ExpressConstants

    # Type alias for file context used in two-pass processing
    alias FileContext = NamedTuple(
      require_map: Hash(String, String),
      function_map: Hash(String, String),
      var_to_function: Hash(String, String),
      var_prefix: Hash(String, Array(String))
    )

    def initialize(
      @all_files : Array(String),
      @base_paths : Array(String),
      @base_path : String,
      @logger : NoirLogger
    )
    end

    # Main entry point: scan all files for router mount patterns
    def scan
      locator = CodeLocator.instance
      main_files = collect_js_files

      # Global collections for two-pass processing
      file_contexts = Hash(String, FileContext).new
      global_deferred_mounts = [] of Tuple(String, String, String, String)

      # PASS 1: Scan all files for top-level mounts and collect nested mounts for later
      main_files.each do |main_file|
        process_file_for_mounts(main_file, locator, file_contexts, global_deferred_mounts)
      end

      # PASS 2: Process all deferred nested mounts now that all top-level mounts are known
      process_deferred_mounts(global_deferred_mounts, file_contexts, locator)
    end

    # Process a single file for router mounts
    private def process_file_for_mounts(
      main_file : String,
      locator : CodeLocator,
      file_contexts : Hash(String, FileContext),
      global_deferred_mounts : Array(Tuple(String, String, String, String))
    )
      content = File.read(main_file, encoding: "utf-8", invalid: :skip)

      # Parse imports
      imports = parse_imports(content, main_file)
      require_map = imports[:require_map]
      function_map = imports[:function_map]
      var_to_function = imports[:var_to_function]

      # Store arrays of prefixes per router variable to support multi-mount scenarios
      var_prefix = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }

      # Scan for .use('/prefix', ...) patterns with explicit path prefix
      content.scan(/(\w+)\.use\s*\(\s*['"]([^'"]+)['"]\s*,\s*/) do |m|
        next unless m.size >= 3

        caller = m[1]
        prefix = m[2]
        match_end = m.end(0) || 0

        process_use_call(content, match_end, caller, prefix, main_file, locator,
                         require_map, function_map, var_to_function, var_prefix, global_deferred_mounts)
      end

      # Scan for .use(router) patterns where prefix is omitted (defaults to '/')
      # The negative lookahead `(?!\s*['"])` prevents matching calls that have a
      # string literal as the first argument, avoiding double processing with the above scan.
      content.scan(/(\w+)\.use\s*\((?!\s*['"])/) do |m|
        next unless m.size >= 2

        caller = m[1]
        prefix = "/"
        # Position scanner to start right after the opening parenthesis
        match_end = (m.begin(0) || 0) + m[0].size

        process_use_call(content, match_end, caller, prefix, main_file, locator,
                         require_map, function_map, var_to_function, var_prefix, global_deferred_mounts)
      end

      # Handle inline factory calls and inline require calls
      process_inline_factory_mounts(content, locator, main_file, function_map, require_map, var_to_function, var_prefix)
      process_inline_require_mounts(content, locator, main_file)

      # Store file context for second pass
      file_contexts[main_file] = {
        require_map:     require_map,
        function_map:    function_map,
        var_to_function: var_to_function,
        var_prefix:      var_prefix,
      }
    rescue e : File::NotFoundError | File::Error | IO::Error
      @logger.debug "Error scanning #{main_file} for router mounts (#{e.class}): #{e.message}"
    end

    # Process a single .use() call
    private def process_use_call(
      content : String,
      match_end : Int32,
      caller : String,
      prefix : String,
      main_file : String,
      locator : CodeLocator,
      require_map : Hash(String, String),
      function_map : Hash(String, String),
      var_to_function : Hash(String, String),
      var_prefix : Hash(String, Array(String)),
      global_deferred_mounts : Array(Tuple(String, String, String, String))
    )
      # Extract arguments with literal-aware scanning
      args = extract_use_call_args(content, match_end)

      # Extract router reference from args
      ref = extract_router_reference(args, require_map, function_map, var_to_function)
      router_var = ref[:router_var]
      router_file_direct = ref[:router_file_direct]

      return unless router_var || router_file_direct

      if caller == "app"
        # Top-level mount
        store_top_level_mount(locator, router_var, router_file_direct, prefix, main_file,
                              require_map, function_map, var_to_function, var_prefix)
      else
        # Nested mount - try to resolve parent prefixes
        processed = store_nested_mount(locator, router_var, router_file_direct, prefix, caller, main_file,
                                       require_map, function_map, var_to_function, var_prefix)

        # Defer if parent prefix not yet known
        unless processed
          deferred_key = router_file_direct || router_var || ""
          global_deferred_mounts << {main_file, caller, prefix, deferred_key} unless deferred_key.empty?
        end
      end
    end

    # Collect all JavaScript/TypeScript files to scan
    private def collect_js_files : Array(String)
      main_files = [] of String

      @all_files.each do |file|
        next if File.directory?(file)
        next unless ExpressConstants::JS_EXTENSIONS.any? { |ext| file.ends_with?(ext) }
        next unless @base_paths.any? { |base| file.starts_with?(base) }
        main_files << file
      end

      # Fallback: if file_map is empty, scan common entrypoints only
      if main_files.empty?
        ExpressConstants::ENTRY_FILENAMES.each do |filename|
          potential_path = File.join(@base_path, filename)
          main_files << potential_path if File.exists?(potential_path)

          ExpressConstants::ENTRY_SUBDIRS.each do |subdir|
            subdir_path = File.join(@base_path, subdir, filename)
            main_files << subdir_path if File.exists?(subdir_path)
          end
        end
      end

      main_files
    end

    # Parse require/import statements from file content
    private def parse_imports(content : String, main_file : String) : NamedTuple(require_map: Hash(String, String), function_map: Hash(String, String), var_to_function: Hash(String, String))
      require_map = Hash(String, String).new
      function_map = Hash(String, String).new
      var_to_function = Hash(String, String).new

      # Pattern: const varName = require('./path/to/file')
      content.scan(/(?:const|let|var)\s+(\w+)\s*=\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        if m.size >= 3
          var_name = m[1]
          require_path = m[2]
          resolved_path = resolve_require_path(main_file, require_path)
          require_map[var_name] = resolved_path if resolved_path
        end
      end

      # Pattern: const { funcA, funcB: aliasB } = require('./path/to/file')
      content.scan(/(?:const|let|var)\s*\{\s*([\s\S]*?)\s*\}\s*=\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        if m.size >= 3
          names = m[1]
          require_path = m[2]
          resolved_path = resolve_require_path(main_file, require_path)
          if resolved_path
            parse_destructured_names(names).each do |name|
              function_map[name] = resolved_path unless name.empty?
            end
          end
        end
      end

      # Pattern: import varName from './path/to/file'
      content.scan(/import\s+(\w+)\s+from\s+['"]([^'"]+)['"]/) do |m|
        if m.size >= 3
          var_name = m[1]
          require_path = m[2]
          resolved_path = resolve_require_path(main_file, require_path)
          require_map[var_name] = resolved_path if resolved_path
        end
      end

      # Pattern: import { funcA, funcB as aliasB } from './path/to/file'
      content.scan(/import\s*\{\s*([\s\S]*?)\s*\}\s*from\s*['"]([^'"]+)['"]/) do |m|
        if m.size >= 3
          names = m[1]
          require_path = m[2]
          resolved_path = resolve_require_path(main_file, require_path)
          if resolved_path
            parse_destructured_names(names).each do |name|
              function_map[name] = resolved_path unless name.empty?
            end
          end
        end
      end

      # Pattern: const varName = functionName()
      content.scan(/(?:const|let|var)\s+(\w+)\s*=\s*(\w+)\s*\(\s*\)/) do |m|
        if m.size >= 3
          var_name = m[1]
          func_name = m[2]
          if function_map.has_key?(func_name)
            var_to_function[var_name] = func_name
          end
        end
      end

      {require_map: require_map, function_map: function_map, var_to_function: var_to_function}
    end

    # Extract router reference from .use() arguments
    private def extract_router_reference(args : String, require_map : Hash(String, String), function_map : Hash(String, String), var_to_function : Hash(String, String)) : NamedTuple(router_var: String?, router_file_direct: String?)
      router_var : String? = nil
      router_file_direct : String? = nil

      # First check for inline require('./path') at the end of args
      if args =~ /require\s*\(\s*['"]([^'"]+)['"]\s*\)\s*$/
        router_file_direct = $1
      # Check for factory function call: createRouter() etc.
      elsif args =~ /(\w+)\s*\(\s*\)\s*$/
        factory_name = $1
        if function_map[factory_name]? || require_map[factory_name]? || var_to_function[factory_name]?
          router_var = factory_name
        end
      end

      # If no inline require/factory, look for identifier or property access
      unless router_file_direct || router_var
        if args =~ /(\w+)\.(\w+)\s*$/ || args =~ /(\w+)\[['"](\w+)['"]\]\s*$/
          router_var = "#{$1}.#{$2}"
        else
          args.scan(/(?<![.=])\b(\w+)\b(?!\s*[(\[=>])/) do |id_match|
            candidate = id_match[1]
            next if ExpressConstants::SKIP_IDENTIFIERS.includes?(candidate)
            router_var = candidate
          end
        end
      end

      {router_var: router_var, router_file_direct: router_file_direct}
    end

    # Push prefix to CodeLocator with deduplication
    private def push_prefix_to_locator(locator : CodeLocator, key : String, prefix : String, debug_msg : String)
      unless locator.all(key).includes?(prefix)
        locator.push(key, prefix)
        @logger.debug debug_msg
      end
    end

    # Get parent prefixes for nested mounts
    private def get_parent_prefixes(caller : String, var_prefix : Hash(String, Array(String)), require_map : Hash(String, String), function_map : Hash(String, String), var_to_function : Hash(String, String), main_file : String, locator : CodeLocator) : Array(String)
      parent_prefixes = var_prefix[caller]?.try(&.dup) || [] of String

      if parent_prefixes.empty?
        if caller_file = require_map[caller]?
          parent_prefixes = locator.all(ExpressConstants.file_key(caller_file))
        elsif caller_func = var_to_function[caller]?
          if caller_file = function_map[caller_func]?
            parent_prefixes = locator.all(ExpressConstants.function_key(caller_file, caller_func))
          end
        elsif caller_file = function_map[caller]?
          parent_prefixes = locator.all(ExpressConstants.function_key(caller_file, caller))
        end
      end

      # Final fallback: use current file's prefix
      if parent_prefixes.empty?
        parent_prefixes = locator.all(ExpressConstants.file_key(main_file))
      end

      parent_prefixes
    end

    # Extract arguments from .use() call using literal-aware scanning
    private def extract_use_call_args(content : String, match_end : Int32) : String
      result = Noir::JSLiteralScanner.extract_paren_content(content, match_end)
      result ? result.content : ""
    end

    # Unified helper: Resolve router variable and store prefix to CodeLocator
    private def resolve_and_store_router_prefix(
      locator : CodeLocator,
      router_var : String?,
      router_file_direct : String?,
      prefix : String,
      main_file : String,
      require_map : Hash(String, String),
      function_map : Hash(String, String),
      var_to_function : Hash(String, String),
      var_prefix : Hash(String, Array(String)),
      log_prefix : String = "Mapped router prefix",
      include_file_level : Bool = false
    )
      # Handle inline require('./path') directly
      if router_file_direct
        router_file = resolve_require_path(main_file, router_file_direct)
        if router_file
          key = ExpressConstants.file_key(router_file)
          push_prefix_to_locator(locator, key, prefix, "#{log_prefix} (inline require): #{router_file} => #{prefix}")
        end
        return
      end

      # Handle path-like router_var as inline require (for deferred mounts)
      if router_var && (router_var.starts_with?("./") || router_var.starts_with?("../") ||
                        router_var.starts_with?("@/") || router_var.starts_with?("~/"))
        router_file = resolve_require_path(main_file, router_var)
        if router_file
          key = ExpressConstants.file_key(router_file)
          push_prefix_to_locator(locator, key, prefix, "#{log_prefix} (inline require): #{router_file} => #{prefix}")
        end
        return
      end

      return unless router_var

      # Check require_map (default imports)
      if router_file = require_map[router_var]?
        key = ExpressConstants.file_key(router_file)
        push_prefix_to_locator(locator, key, prefix, "#{log_prefix}: #{router_file} => #{prefix}")
        var_prefix[router_var] << prefix unless var_prefix[router_var].includes?(prefix)
        return
      end

      # Check var_to_function (factory variable assignments)
      if func_name = var_to_function[router_var]?
        if router_file = function_map[func_name]?
          key = ExpressConstants.function_key(router_file, func_name)
          push_prefix_to_locator(locator, key, prefix, "#{log_prefix} (factory var): #{router_file}:#{func_name} => #{prefix}")
          var_prefix[router_var] << prefix unless var_prefix[router_var].includes?(prefix)
        end
        return
      end

      # Check function_map (destructured imports)
      if router_file = function_map[router_var]?
        key = ExpressConstants.function_key(router_file, router_var)
        push_prefix_to_locator(locator, key, prefix, "#{log_prefix} (factory direct): #{router_file}:#{router_var} => #{prefix}")
        if include_file_level
          file_key = ExpressConstants.file_key(router_file)
          push_prefix_to_locator(locator, file_key, prefix, "#{log_prefix} (file-level): #{router_file} => #{prefix}")
        end
        var_prefix[router_var] << prefix unless var_prefix[router_var].includes?(prefix)
        return
      end

      # Handle property-based router access: routers.user or routers['user']
      if router_var.includes?(".")
        parts = router_var.split(".", 2)
        base_obj = parts[0]
        prop_name = parts[1]?
        if prop_name
          router_file = require_map[base_obj]? || function_map[base_obj]?
          if router_file
            key = ExpressConstants.function_key(router_file, prop_name)
            push_prefix_to_locator(locator, key, prefix, "#{log_prefix} (property): #{router_file}:#{prop_name} => #{prefix}")
            # Also store file-level key for router-instance exports (not factory functions)
            if include_file_level
              file_key = ExpressConstants.file_key(router_file)
              push_prefix_to_locator(locator, file_key, prefix, "#{log_prefix} (property file-level): #{router_file} => #{prefix}")
            end
          end
        end
        var_prefix[router_var] << prefix unless var_prefix[router_var].includes?(prefix)
      end
    end

    # Store a top-level mount (caller == "app") to CodeLocator
    private def store_top_level_mount(
      locator : CodeLocator,
      router_var : String?,
      router_file_direct : String?,
      prefix : String,
      main_file : String,
      require_map : Hash(String, String),
      function_map : Hash(String, String),
      var_to_function : Hash(String, String),
      var_prefix : Hash(String, Array(String))
    )
      resolve_and_store_router_prefix(
        locator, router_var, router_file_direct, prefix, main_file,
        require_map, function_map, var_to_function, var_prefix,
        log_prefix: "Mapped router prefix",
        include_file_level: true
      )
    end

    # Store a nested mount (caller != "app") with proper parent prefix resolution
    # Returns true if processed, false if should be deferred
    private def store_nested_mount(
      locator : CodeLocator,
      router_var : String?,
      router_file_direct : String?,
      prefix : String,
      caller : String,
      main_file : String,
      require_map : Hash(String, String),
      function_map : Hash(String, String),
      var_to_function : Hash(String, String),
      var_prefix : Hash(String, Array(String))
    ) : Bool
      parent_prefixes = get_parent_prefixes(caller, var_prefix, require_map, function_map, var_to_function, main_file, locator)

      # If no parent prefixes found, defer for later processing
      return false if parent_prefixes.empty?

      parent_prefixes.each do |parent_prefix|
        combined = Noir::URLPath.join(parent_prefix, prefix)
        resolve_and_store_router_prefix(
          locator, router_var, router_file_direct, combined, main_file,
          require_map, function_map, var_to_function, var_prefix,
          log_prefix: "Mapped nested router prefix",
          include_file_level: true
        )
      end

      true
    end

    # Process inline factory calls: app.use('/prefix', createRouter())
    private def process_inline_factory_mounts(
      content : String,
      locator : CodeLocator,
      main_file : String,
      function_map : Hash(String, String),
      require_map : Hash(String, String),
      var_to_function : Hash(String, String),
      var_prefix : Hash(String, Array(String))
    )
      content.scan(/(\w+)\.use\s*\(\s*['"]([^'"]+)['"]\s*,\s*(\w+)\s*\(\s*\)\s*\)/) do |m|
        next unless m.size >= 4

        caller = m[1]
        prefix = m[2]
        func_name = m[3]
        router_file = function_map[func_name]?

        if caller == "app"
          # Top-level mount
          if router_file
            key = ExpressConstants.function_key(router_file, func_name)
            push_prefix_to_locator(locator, key, prefix, "Mapped router prefix (inline factory): #{router_file}:#{func_name} => #{prefix}")
          end
        else
          # Nested mount
          parent_prefixes = get_parent_prefixes(caller, var_prefix, require_map, function_map, var_to_function, main_file, locator)

          if !parent_prefixes.empty? && router_file
            parent_prefixes.each do |parent_prefix|
              combined = Noir::URLPath.join(parent_prefix, prefix)
              key = ExpressConstants.function_key(router_file, func_name)
              push_prefix_to_locator(locator, key, combined, "Mapped nested router prefix: #{router_file}:#{func_name} => #{combined}")
            end
          end
        end
      end
    end

    # Process inline require calls: app.use('/prefix', require('./path'))
    private def process_inline_require_mounts(content : String, locator : CodeLocator, main_file : String)
      content.scan(/app\.use\s*\(\s*['"]([^'"]+)['"]\s*,\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        next unless m.size >= 3

        prefix = m[1]
        require_path = m[2]
        resolved_path = resolve_require_path(main_file, require_path)

        if resolved_path
          key = ExpressConstants.file_key(resolved_path)
          push_prefix_to_locator(locator, key, prefix, "Mapped router prefix (inline): #{resolved_path} => #{prefix}")
        end
      end
    end

    # Process deferred mounts in pass 2
    private def process_deferred_mounts(
      global_deferred_mounts : Array(Tuple(String, String, String, String)),
      file_contexts : Hash(String, FileContext),
      locator : CodeLocator
    )
      global_deferred_mounts.each do |main_file, caller, prefix, router_var|
        ctx = file_contexts[main_file]?
        next unless ctx

        require_map = ctx[:require_map]
        function_map = ctx[:function_map]
        var_to_function = ctx[:var_to_function]
        var_prefix = ctx[:var_prefix]

        parent_prefixes = get_parent_prefixes(caller, var_prefix, require_map, function_map, var_to_function, main_file, locator)
        next if parent_prefixes.empty?

        parent_prefixes.each do |parent_prefix|
          combined = Noir::URLPath.join(parent_prefix, prefix)
          store_deferred_mount(locator, router_var, combined, main_file, require_map, function_map, var_to_function, var_prefix)
        end
      end
    end

    # Store a single deferred mount
    private def store_deferred_mount(
      locator : CodeLocator,
      router_var : String,
      combined : String,
      main_file : String,
      require_map : Hash(String, String),
      function_map : Hash(String, String),
      var_to_function : Hash(String, String),
      var_prefix : Hash(String, Array(String))
    )
      resolve_and_store_router_prefix(
        locator, router_var, nil, combined, main_file,
        require_map, function_map, var_to_function, var_prefix,
        log_prefix: "Mapped deferred nested router prefix",
        include_file_level: true
      )
    end

    # Parse destructured import/require names from JavaScript/TypeScript syntax.
    #
    # This is a heuristic parser that extracts variable names from destructuring patterns.
    # It handles the most common patterns found in Express.js codebases but is not a
    # complete JavaScript parser.
    #
    # ## Algorithm
    #
    # 1. **Preprocessing**: Strip comments (block and line) to simplify parsing.
    #
    # 2. **Tokenization by comma**: Split the input into items at top-level commas only.
    #    We track nesting depth for braces `{}`, brackets `[]`, and parentheses `()`,
    #    as well as string literal state (single/double quotes, backticks).
    #    Commas inside nested structures or strings are preserved.
    #
    # 3. **Name extraction**: For each item, extract the local variable name by:
    #    - Removing spread operator (`...`)
    #    - Removing default values (`= defaultValue`)
    #    - Handling ES6 import aliases (`original as alias` → `alias`)
    #    - Handling object property renaming (`key: localName` → `localName`)
    #    - Recursively parsing nested destructuring patterns
    #
    # ## Supported Patterns
    #
    # ```javascript
    # // Simple destructuring
    # { a, b, c }                        → ["a", "b", "c"]
    #
    # // With aliases (ES6 import style)
    # { foo as bar }                     → ["bar"]
    #
    # // With renaming (object destructuring style)
    # { originalKey: localVar }          → ["localVar"]
    #
    # // With defaults
    # { a = 1, b = "default" }           → ["a", "b"]
    #
    # // Spread operator
    # { ...rest }                        → ["rest"]
    #
    # // Nested destructuring (recursive)
    # { outer: { inner } }               → ["inner"]
    # { arr: [first, second] }           → ["first", "second"]
    #
    # // Mixed patterns
    # { a, b: renamed, c = 3, ...rest }  → ["a", "renamed", "c", "rest"]
    # ```
    #
    # ## Known Limitations
    #
    # - **Computed property names**: `{ [expr]: value }` is not supported.
    # - **Complex default expressions**: Defaults with nested function calls or
    #   objects containing commas may cause issues (though string literals are handled).
    # - **Template literal interpolation**: Backtick strings with `${...}` containing
    #   quotes may confuse the string state tracking.
    # - **Escaped characters**: Only simple backslash-quote escapes are handled;
    #   unicode escapes or other complex escapes are not.
    #
    # ## Design Decision
    #
    # This approach was chosen over a full parser because:
    # 1. We only need variable names, not full AST
    # 2. The patterns in real Express.js code are typically simple
    # 3. A full JS parser would be significantly more complex and slower
    # 4. False negatives (missing a name) are acceptable; false positives are rare
    #
    private def parse_destructured_names(names : String) : Array(String)
      # Step 1: Remove comments to simplify parsing
      cleaned = names
        .gsub(/\/\*.*?\*\//m, "")  # Block comments
        .gsub(/\/\/[^\n]*/, "")    # Line comments

      # Step 2: Split into items at top-level commas
      items = split_at_top_level_commas(cleaned)

      # Step 3: Extract variable names from each item
      extracted = [] of String
      items.each do |item|
        name = item.strip
        next if name.empty?

        # Remove spread operator: `...rest` → `rest`
        name = name.sub(/^\.\.\./, "").strip

        # Remove default value (first pass): `a = 1` → `a`
        name = name.split("=", 2)[0].strip

        # Handle ES6 import alias syntax: `original as alias` → `alias`
        if name.includes?(" as ")
          parts = name.split(/\s+as\s+/, 2)
          name = parts.size == 2 ? parts[1].strip : name
        # Handle object property renaming: `key: localName` → `localName`
        elsif name.includes?(":")
          parts = name.split(":", 2)
          name = parts.size == 2 ? parts[1].strip : name
        end

        # Handle nested object destructuring: `{ inner }` → recurse
        if name.starts_with?("{") && name.ends_with?("}")
          inner = name[1..-2]
          extracted.concat(parse_destructured_names(inner))
          next
        # Handle nested array destructuring: `[ first, second ]` → recurse
        elsif name.starts_with?("[") && name.ends_with?("]")
          inner = name[1..-2]
          extracted.concat(parse_destructured_names(inner))
          next
        end

        # Remove any remaining default value after alias/rename processing
        # This handles cases like `key: localName = default`
        name = name.split("=", 2)[0].strip
        extracted << name unless name.empty?
      end

      extracted
    end

    # Split a string at top-level commas, respecting nesting and string literals.
    #
    # This is a literal-aware tokenizer that splits on commas only when they are
    # not inside nested structures (braces, brackets, parentheses) or string literals.
    #
    # Example: "a, b = {x: 1, y: 2}, c" → ["a", " b = {x: 1, y: 2}", " c"]
    #
    private def split_at_top_level_commas(input : String) : Array(String)
      items = [] of String
      current = ""
      depth_brace = 0    # Tracks {} nesting (objects, blocks)
      depth_bracket = 0  # Tracks [] nesting (arrays)
      depth_paren = 0    # Tracks () nesting (function calls, grouping)
      in_string : Char? = nil  # Tracks if we're inside a string and which quote char
      prev_char : Char? = nil  # For detecting escaped quotes

      input.each_char do |ch|
        # --- String literal handling ---
        # When inside a string, accumulate characters until we hit the closing quote
        if in_string
          current += ch
          # End of string: same quote char, not escaped by backslash
          if ch == in_string && prev_char != '\\'
            in_string = nil
          end
          prev_char = ch
          next
        end

        # Start of a string literal
        if ch == '"' || ch == '\'' || ch == '`'
          in_string = ch
          current += ch
          prev_char = ch
          next
        end

        # --- Nesting depth tracking ---
        # Track depth so we only split on commas at the top level
        case ch
        when '{'
          depth_brace += 1
        when '}'
          depth_brace -= 1 if depth_brace > 0
        when '['
          depth_bracket += 1
        when ']'
          depth_bracket -= 1 if depth_bracket > 0
        when '('
          depth_paren += 1
        when ')'
          depth_paren -= 1 if depth_paren > 0
        when ','
          # Only split at top-level commas (not inside any nested structure)
          if depth_brace == 0 && depth_bracket == 0 && depth_paren == 0
            items << current
            current = ""
            prev_char = ch
            next
          end
        end

        current += ch
        prev_char = ch
      end

      # Don't forget the last item (no trailing comma)
      items << current unless current.empty?

      items
    end

    # Resolve a require path relative to the requiring file
    # Follows Node.js module resolution: file -> file+ext -> directory/index
    private def resolve_require_path(from_file : String, require_path : String) : String?
      is_relative = require_path.starts_with?(".")
      is_root_alias = require_path.starts_with?("@/") || require_path.starts_with?("~/")
      return nil unless is_relative || is_root_alias

      resolved = if is_root_alias
                   alias_path = require_path.starts_with?("@/") ? require_path.lchop("@/") : require_path.lchop("~/")
                   File.expand_path(alias_path, @base_path)
                 else
                   base_dir = File.dirname(from_file)
                   File.expand_path(require_path, base_dir)
                 end

      # Case 1: The resolved path is a file that exists
      return resolved if File.file?(resolved)

      # Case 2: The path has no extension, try adding common JS/TS extensions
      if File.extname(require_path).empty?
        [".js", ".ts", ".jsx", ".tsx"].each do |ext|
          with_ext = "#{resolved}#{ext}"
          return with_ext if File.file?(with_ext)
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
