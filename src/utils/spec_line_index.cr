require "json"
require "yaml"
require "./yaml"

module Noir
  # Where each key of a structured specification document is declared.
  #
  # The specification analyzers read their documents through `JSON.parse` /
  # `YAML.parse`, and `JSON::Any` / `YAML::Any` keep no source positions at
  # all. That is why an OpenAPI scan could say an operation came from
  # `openapi.yaml` but never which of its 8000 lines — the parser threw the
  # position away before the analyzer saw the node.
  #
  # This walks the same text a second time with the position-aware pull
  # parsers and records the 1-based line of every mapping key under `root`,
  # down to `max_depth` levels. For OpenAPI that is `paths` -> path ->
  # method, i.e. `root: "paths", max_depth: 2`, which is exactly the line an
  # operation is declared on.
  #
  # Only the subtree under `root` is walked; everything else is skipped
  # without being materialized, so indexing a large document costs a scan of
  # its `paths` section rather than a second full parse tree.
  #
  # Mapping keys only. A sequence value is skipped whole, so a document that
  # addresses operations by array position (Postman's nested `item`) is not
  # served by this and gets no line rather than a guessed one.
  class SpecLineIndex
    # Key paths are flattened into one string so lookups don't allocate an
    # array per query. NUL cannot appear in a JSON/YAML key that the parsers
    # hand back as a scalar, so it is an unambiguous separator.
    SEPARATOR = '\u0000'

    # A document bigger than this is not indexed. Both walks are streaming,
    # but the index itself is proportional to the number of keys under
    # `root`, and noir scans untrusted repositories.
    MAX_CONTENT_BYTES = 64 * 1024 * 1024

    getter entries : Hash(String, Int32)

    def initialize(@entries : Hash(String, Int32) = Hash(String, Int32).new)
    end

    def self.empty : SpecLineIndex
      new
    end

    # Index a JSON document. `root` names the single top-level key whose
    # subtree is indexed; `nil` indexes the document mapping itself, which is
    # what a document keyed directly by route name needs.
    def self.json(content : String, root : String? = nil, max_depth : Int32 = 2) : SpecLineIndex
      return empty if content.bytesize > MAX_CONTENT_BYTES
      entries = Hash(String, Int32).new
      begin
        pull = JSON::PullParser.new(content)
        if pull.kind.begin_object?
          if root.nil?
            walk_json(pull, "", entries, 1, max_depth)
          else
            pull.read_begin_object
            until pull.kind.end_object?
              key_line = pull.line_number
              key = pull.read_object_key
              if key == root
                entries[key] = key_line
                walk_json(pull, key, entries, 1, max_depth)
              else
                pull.skip
              end
            end
          end
        end
      rescue
        # A malformed document simply has no index; the analyzer's own parse
        # is what decides whether it yields endpoints.
      end
      new(entries)
    end

    # Index a YAML document (first document of the stream). See `json` for
    # what `root` means.
    def self.yaml(content : String, root : String? = nil, max_depth : Int32 = 2) : SpecLineIndex
      return empty if content.bytesize > MAX_CONTENT_BYTES

      entries, complete = build_yaml(content, root, max_depth)
      return new(entries) if complete

      # `parse_yaml` recovers a document libyaml rejects for a stray tab on an
      # otherwise-blank line by blanking those lines; the analyzer therefore
      # has endpoints from text this walk choked on. Retry on the same
      # recovered text — it is line-for-line identical — so the operations
      # after the tab get their lines too.
      recovered, recovered_complete = build_yaml(blank_whitespace_only_lines(content), root, max_depth)
      return new(recovered) if recovered_complete || recovered.size > entries.size
      new(entries)
    end

    # `{entries, no exception was raised}`. Entries recorded before a failure
    # are still correct, just incomplete, so the caller decides whether to
    # keep them or prefer a recovered pass.
    private def self.build_yaml(content : String, root : String?,
                                max_depth : Int32) : Tuple(Hash(String, Int32), Bool)
      entries = Hash(String, Int32).new
      begin
        parser = YAML::PullParser.new(content)
        parser.read_stream_start
        parser.read_document_start
        if parser.kind.mapping_start?
          if root.nil?
            walk_yaml(parser, "", entries, 1, max_depth)
          else
            parser.read_mapping_start
            until parser.kind.mapping_end?
              key_line = parser.start_line
              break unless parser.kind.scalar?
              key = parser.read_scalar
              if key == root
                entries[key] = key_line
                walk_yaml(parser, key, entries, 1, max_depth)
              else
                parser.skip
              end
            end
          end
        end
      rescue
        # See `json`.
        return {entries, false}
      end
      {entries, true}
    end

    private def self.walk_json(pull : JSON::PullParser, prefix : String,
                               entries : Hash(String, Int32),
                               depth : Int32, max_depth : Int32) : Nil
      unless pull.kind.begin_object?
        pull.skip
        return
      end

      pull.read_begin_object
      until pull.kind.end_object?
        key_line = pull.line_number
        key = pull.read_object_key
        child = prefix.empty? ? key : "#{prefix}#{SEPARATOR}#{key}"
        entries[child] = key_line
        if depth >= max_depth
          pull.skip
        else
          walk_json(pull, child, entries, depth + 1, max_depth)
        end
      end
      pull.read_end_object
    end

    private def self.walk_yaml(parser : YAML::PullParser, prefix : String,
                               entries : Hash(String, Int32),
                               depth : Int32, max_depth : Int32) : Nil
      # An alias (`*shared`) or a scalar here is not a mapping to descend
      # into; skipping keeps the parser in step with the document.
      unless parser.kind.mapping_start?
        parser.skip
        return
      end

      parser.read_mapping_start
      until parser.kind.mapping_end?
        key_line = parser.start_line
        break unless parser.kind.scalar?
        key = parser.read_scalar
        child = prefix.empty? ? key : "#{prefix}#{SEPARATOR}#{key}"
        entries[child] = key_line
        if depth >= max_depth
          parser.skip
        else
          walk_yaml(parser, child, entries, depth + 1, max_depth)
        end
      end
      parser.read_mapping_end
    end

    def empty? : Bool
      @entries.empty?
    end

    # 1-based line the given key path is declared on, or nil when the
    # document has no such key at an indexed depth.
    def line(*keys : String) : Int32?
      @entries[keys.join(SEPARATOR)]?
    end

    def line(keys : Array(String)) : Int32?
      @entries[keys.join(SEPARATOR)]?
    end
  end
end
