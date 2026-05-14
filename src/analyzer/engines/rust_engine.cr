require "../../models/analyzer"
require "../../miniparsers/rust_callee_extractor"

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

    protected def attach_rust_callees(endpoint : Endpoint, callees : Array(Noir::RustCalleeExtractor::Entry))
      Noir::RustCalleeExtractor.attach_to(endpoint, callees)
    end

    protected def extract_rust_function_body(lines : Array(String), start_index : Int32) : Tuple(String, Int32)?
      function_body = extract_rust_function_body_with_end(lines, start_index)
      return unless function_body

      body, body_start_line, _ = function_body
      {body, body_start_line}
    end

    protected def extract_rust_function_body_with_end(lines : Array(String), start_index : Int32) : Tuple(String, Int32, Int32)?
      return if start_index >= lines.size
      return if Noir::RustCalleeExtractor.strip_comment(lines[start_index]).includes?(";")

      body_lines = [] of String
      body_start_line = start_index + 2
      found_opening_brace = false
      depth = 0
      in_block_comment = false

      (start_index...lines.size).each do |index|
        raw_line = lines[index]
        line, in_block_comment = Noir::RustCalleeExtractor.strip_comment_with_state(raw_line, in_block_comment)

        unless found_opening_brace
          return if index > start_index && line.strip.match(/^(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+[A-Za-z_]\w*\b/)

          brace_index = line.index('{')
          next unless brace_index

          found_opening_brace = true
          depth = 1
          tail = line[(brace_index + 1)..].strip
          body_start_line = index + 1

          if close_index = tail.index('}')
            open_count = tail.count('{')
            close_count = tail.count('}')
            if depth + open_count - close_count <= 0
              close_index = tail.rindex('}') || close_index
              return {tail[0, close_index].strip, body_start_line, index}
            end
          end

          if tail.empty?
            body_start_line = index + 2
          else
            body_lines << tail
            depth += tail.count('{') - tail.count('}')
          end
          next
        end

        stripped = line.strip
        open_count = stripped.count('{')
        close_count = stripped.count('}')

        if close_count > 0 && depth + open_count - close_count <= 0
          if close_index = line.index('}')
            close_index = line.rindex('}') || close_index
            before_close = line[0, close_index].strip
            body_lines << before_close unless before_close.empty?
          end
          return {body_lines.join("\n"), body_start_line, index}
        end

        body_lines << raw_line
        depth += open_count - close_count
      end

      return unless found_opening_brace

      {body_lines.join("\n"), body_start_line, lines.size - 1}
    end
  end
end
