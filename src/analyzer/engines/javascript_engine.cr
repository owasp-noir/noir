require "../../models/analyzer"

module Analyzer::Javascript
  abstract class JavascriptEngine < Analyzer
    # Default extension set for JavaScript/TypeScript source files.
    # Analyzers with a different filter (e.g. Nitro adds `.mts`, NestJS JS
    # only uses `.js`/`.jsx`) pass their own list to `parallel_file_scan`.
    DEFAULT_EXTENSIONS = [".js", ".ts", ".jsx", ".tsx"]

    # Walk the project tree concurrently, invoking the block for each
    # readable source file whose extension matches. JS/TS analyzers vary
    # in the exact filter (plain JS vs TS vs .mjs vs .tsx), so the filter
    # is an argument with a sensible default.
    #
    # Name-consistent with the other engines' `parallel_file_scan` helpers.
    protected def parallel_file_scan(extensions : Array(String) = DEFAULT_EXTENSIONS, &block : String -> Nil) : Nil
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_files(channel)

        parallel_analyze(channel) do |path|
          next if File.directory?(path)
          next unless File.exists?(path)
          next unless extensions.any? { |ext| path.ends_with?(ext) }

          begin
            block.call(path)
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
          end
        end
      rescue e
        logger.debug e
      end
    end
  end
end
