require "../../models/analyzer"
require "../../miniparsers/ruby_callee_extractor"

module Analyzer::Ruby
  abstract class RubyEngine < Analyzer
    HTTP_VERBS = ["get", "post", "put", "delete", "patch", "head", "options"]

    # Minitest's `*_test.rb` and RSpec's `*_spec.rb` conventions are
    # rigid in Ruby — `rake test` / `mri test` only run files matching
    # the first, and `rspec` discovers the second. Production Ruby
    # never adopts either filename, so the suffix check is safe for
    # every Ruby analyzer (sinatra, grape, roda, hanami). Promoted
    # from `Analyzer::Ruby::Sinatra` (#1571) so the rest of the
    # family stays in sync.
    def self.ruby_test_path?(path : String) : Bool
      base = File.basename(path)
      base.ends_with?("_test.rb") || base.ends_with?("_spec.rb")
    end

    # Match the `<verb> "<path>"` idiom on a single line and return the first
    # endpoint found, or an empty endpoint if none match. Shared by Hanami
    # and Sinatra (Rails uses a different per-line-multi-match shape).
    def line_to_endpoint(content : String, details : Details? = nil) : Endpoint
      HTTP_VERBS.each do |verb|
        # Reject method calls (`headers.delete 'content-length'`,
        # `obj.get(:foo)`, …) that share a name with a DSL verb. The
        # Sinatra route DSL always invokes the verb at a fresh
        # statement boundary, never via a receiver. A negative
        # lookbehind on `.` and word chars covers both
        # `headers.delete` and `xdelete` (some unrelated identifier
        # ending in the verb).
        content.scan(/(?<![.\w])#{verb}\s+['"](.+?)['"]/) do |match|
          if match.size > 1
            if details
              return Endpoint.new(match[1], verb.upcase, details)
            else
              return Endpoint.new(match[1], verb.upcase)
            end
          end
        end
      end
      Endpoint.new("", "")
    end

    # Locate the directories that host a known framework anchor file
    # (e.g. `config/routes.rb`) anywhere under `base_paths`. Returns the
    # framework root for each match, i.e. the anchor's path with the
    # relative suffix stripped. Lets analyzers stop assuming the framework
    # root is `@base_path` and survive monorepos where it lives in a
    # subdirectory (`App/`, `backend/`, ...).
    protected def discover_framework_roots(anchor : String) : Array(String)
      suffix = anchor.starts_with?("/") ? anchor : "/#{anchor}"
      roots = [] of String

      all_files.each do |file|
        next unless file.ends_with?(suffix)
        next unless base_paths.any? do |base|
                      prefix = base.ends_with?("/") ? base : "#{base}/"
                      file.starts_with?(prefix) || file == "#{base}#{suffix}"
                    end

        root = file[0, file.size - suffix.size]
        roots << root unless roots.includes?(root)
      end

      roots
    end

    # Walk the project file tree in parallel, invoking the block for each
    # readable non-directory file. Used by analyzers that scan the whole
    # tree (Sinatra); Rails/Hanami target specific config files directly.
    #
    # Name-consistent with the other engines' `parallel_file_scan` helpers.
    protected def parallel_file_scan(&block : String -> Nil) : Nil
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_files(channel)

        parallel_analyze(channel) do |path|
          next if File.directory?(path)
          next unless File.exists?(path)

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

    protected def attach_ruby_callees(endpoint : Endpoint, callees : Array(Noir::RubyCalleeExtractor::Entry))
      Noir::RubyCalleeExtractor.attach_to(endpoint, callees)
    end

    protected def extract_ruby_do_block(lines : Array(String), start_index : Int32) : Tuple(String, Int32)?
      return if start_index >= lines.size

      start_line = Noir::RubyCalleeExtractor.strip_comment(lines[start_index]).strip
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
        depth += ruby_do_block_open_delta(tail)
      end

      index = start_index + 1
      while index < lines.size
        raw_body_line = lines[index]
        body_line = Noir::RubyCalleeExtractor.strip_comment(raw_body_line).strip

        if ruby_closes_block?(body_line)
          depth -= 1
          break if depth == 0
          body_lines << raw_body_line
          index += 1
          next
        end

        body_lines << raw_body_line
        depth += ruby_do_block_open_delta(body_line)
        index += 1
      end

      {body_lines.join("\n"), body_start_line}
    end

    protected def ruby_do_block_open_delta(line : String) : Int32
      return 0 if line.empty?
      return 1 if line.match(/\bdo\b/) && !line.match(/\bend\b/)
      return 1 if line.match(/(?:^|=[^=>])\s*(if|unless|case|begin|while|until|for|class|module|def)\b/) && !line.match(/\bend\b/)
      0
    end

    private def ruby_closes_block?(line : String) : Bool
      !!line.match(/^end\b/)
    end
  end
end
