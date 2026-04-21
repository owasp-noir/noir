require "../../models/analyzer"

module Analyzer::Rust
  abstract class RustEngine < Analyzer
    def analyze
      parallel_file_scan do |path|
        result.concat(analyze_file(path))
      end
      result
    end

    abstract def analyze_file(path : String) : Array(Endpoint)

    # `.rs` extension filter baked in. Subclasses that want a different scan
    # shape (e.g. a post-pass after the file walk) can override `analyze`
    # and call this helper directly; the default `analyze` above is the
    # simpler path.
    protected def parallel_file_scan(&block : String -> Nil) : Nil
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_files(channel)

        parallel_analyze(channel) do |path|
          next if File.directory?(path)
          next unless File.exists?(path) && File.extname(path) == ".rs"

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
