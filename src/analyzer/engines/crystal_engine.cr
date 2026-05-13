require "../../models/analyzer"
require "../../miniparsers/crystal_callee_extractor"

module Analyzer::Crystal
  abstract class CrystalEngine < Analyzer
    def analyze
      parallel_file_scan do |path|
        result.concat(analyze_file(path))
      end
      result
    end

    abstract def analyze_file(path : String) : Array(Endpoint)

    # `.cr` extension filter plus `lib/` exclusion baked in (shards puts
    # dependencies under `lib/` and we don't want to analyze them).
    # Subclasses that need a custom scan shape can override `analyze`
    # (e.g. Amber/Kemal run a public-dir post-pass after the file walk).
    protected def parallel_file_scan(&block : String -> Nil) : Nil
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_files(channel)

        parallel_analyze(channel) do |path|
          next if File.directory?(path)
          next unless File.exists?(path) && File.extname(path) == ".cr"
          next if path.includes?("lib")

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

    protected def attach_crystal_callees(endpoint : Endpoint, callees : Array(Noir::CrystalCalleeExtractor::Entry))
      Noir::CrystalCalleeExtractor.attach_to(endpoint, callees)
    end

    protected def extract_crystal_do_block(lines : Array(String), start_index : Int32) : Tuple(String, Int32)?
      return if start_index >= lines.size

      start_line = Noir::CrystalCalleeExtractor.strip_comment(lines[start_index]).strip
      match = start_line.match(/\bdo\b(?:\s*\|[^|]*\|)?(.*)$/)
      return unless match

      body_lines = [] of String
      body_start_line = start_index + 2
      depth = 1
      tail = match[1].strip
      tail = tail[1, tail.size - 1].strip if tail.starts_with?(";")

      unless tail.empty?
        body_start_line = start_index + 1
        if m = tail.match(/^(.*?)(?:;\s*)?end\b/)
          return {m[1].strip, body_start_line}
        end

        body_lines << tail
        depth += crystal_do_block_open_delta(tail)
      end

      index = start_index + 1
      while index < lines.size
        raw_body_line = lines[index]
        body_line = Noir::CrystalCalleeExtractor.strip_comment(raw_body_line).strip

        if crystal_closes_block?(body_line)
          depth -= 1
          break if depth == 0
          body_lines << raw_body_line
          index += 1
          next
        end

        body_lines << raw_body_line
        depth += crystal_do_block_open_delta(body_line)
        index += 1
      end

      {body_lines.join("\n"), body_start_line}
    end

    protected def extract_crystal_def_block(lines : Array(String), start_index : Int32) : Tuple(String, Int32)?
      return if start_index >= lines.size

      def_line = Noir::CrystalCalleeExtractor.strip_comment(lines[start_index]).strip
      if semicolon_index = def_line.index(';')
        tail = def_line[(semicolon_index + 1)..].strip
        if m = tail.match(/^(.*?)(?:;\s*)?end\b/)
          return {m[1].strip, start_index + 1}
        end
      end

      body_lines = [] of String
      body_start_line = start_index + 2
      depth = 1
      index = start_index + 1

      while index < lines.size
        raw_body_line = lines[index]
        body_line = Noir::CrystalCalleeExtractor.strip_comment(raw_body_line).strip

        if crystal_closes_block?(body_line)
          depth -= 1
          break if depth == 0
          body_lines << raw_body_line
          index += 1
          next
        end

        body_lines << raw_body_line
        depth += crystal_do_block_open_delta(body_line)
        index += 1
      end

      {body_lines.join("\n"), body_start_line}
    end

    protected def crystal_do_block_open_delta(line : String) : Int32
      return 0 if line.empty?
      return 1 if line.match(/\bdo\b/) && !line.match(/\bend\b/)
      return 1 if line.match(/(?:^|=[^=>])\s*(if|unless|case|begin|while|until|for|class|module|def|macro)\b/) && !line.match(/\bend\b/)
      0
    end

    private def crystal_closes_block?(line : String) : Bool
      !!line.match(/^end\b/)
    end
  end
end
