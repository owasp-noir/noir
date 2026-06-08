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

    # Standard set of HTTP methods that `axum::routing::any(...)` /
    # actix `web::route()` / similar method-agnostic registrations
    # accept. Mirrors the Go `fan_out_verbs` set so output formats
    # see real HTTP methods instead of a non-HTTP "ANY" string.
    ANY_FAN_OUT_VERBS = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    # Expand `any` / `all` (case-insensitive) into the seven
    # canonical HTTP methods. Anything else passes through as a
    # single-element list.
    def self.fan_out_verbs(verb : String) : Array(String)
      case verb.upcase
      when "ANY", "ALL"
        ANY_FAN_OUT_VERBS
      else
        [verb]
      end
    end

    # `.rs` extension filter baked in. Subclasses that want a different scan
    # shape (e.g. a post-pass after the file walk) can override `analyze`
    # and call this helper directly; the default `analyze` above is the
    # simpler path.
    protected def parallel_file_scan(&block : String -> Nil) : Nil
      begin
        parallel_analyze(all_files) do |path|
          next if File.directory?(path)
          next unless File.exists?(path) && File.extname(path) == ".rs"
          next if RustEngine.test_path?(path)

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

    # Cargo convention: every `.rs` immediately under a crate's
    # `tests/` directory is an integration-test binary, never a
    # production endpoint. The `_test.rs` / `_tests.rs` suffix is
    # equally rigid for unit tests in sibling files. Framework
    # repos (rocket/Rocket's `core/codegen/tests/`, actix-web's
    # `actix-web-codegen/tests/`, poem's `poem-openapi/tests/`)
    # all park hundreds of route registrations under one of these
    # patterns. Promoted from `axum.cr#test_only_path?` (#1569) to
    # the shared engine so the rest of the Rust family benefits.
    def self.test_path?(path : String) : Bool
      return true if path.includes?("/tests/")
      # Cargo's `benches/` directory holds `cargo bench` harnesses
      # (`Router::new().route(...)` scaffolding for throughput tests),
      # never production endpoints — axum/tide park route-building
      # benchmarks here. Exclude it like `tests/`.
      return true if path.includes?("/benches/")
      base = File.basename(path)
      base == "tests.rs" || base.ends_with?("_test.rs") || base.ends_with?("_tests.rs")
    end

    # Scan the source for `#[cfg(test)]` annotations, then capture
    # the byte range of the following `mod`/`fn`/`impl` block via
    # simple brace counting. String/char literals are skipped so a
    # `{` inside `"foo {"` doesn't shift the depth. Rust lifetimes
    # like `'a` look like char literals to a naive quote scanner
    # and would otherwise drop the close-brace search into oblivion
    # — see `skip_char_or_lifetime`.
    #
    # Shared with all Rust analyzers: axum's `extract/path/mod.rs`,
    # salvo's `crates/core/src/routing.rs`, and similar framework
    # source files mix production routes with `#[cfg(test)] mod
    # tests { ... }` blocks. Each analyzer that uses tree-sitter
    # can call this once per file, then drop any route call whose
    # `ts_node_start_byte` falls in one of the returned ranges.
    def self.collect_cfg_test_regions(source : String) : Array(Tuple(Int32, Int32))
      regions = [] of Tuple(Int32, Int32)
      bytes = source.to_slice
      pattern = /\#\s*\[\s*cfg\s*\(\s*test\s*\)\s*\]/
      source.scan(pattern) do |match|
        attr_start = match.begin || next
        brace_idx = find_block_open_brace(bytes, attr_start + 1)
        next unless brace_idx
        close_idx = find_matching_close_brace(bytes, brace_idx)
        next unless close_idx
        regions << {attr_start, close_idx + 1}
      end
      regions
    end

    def self.inside_test_region?(node : LibTreeSitter::TSNode, regions : Array(Tuple(Int32, Int32))) : Bool
      return false if regions.empty?
      start_byte = LibTreeSitter.ts_node_start_byte(node).to_i
      regions.any? { |s, e| start_byte >= s && start_byte < e }
    end

    private def self.find_block_open_brace(bytes : Slice(UInt8), from : Int32) : Int32?
      i = from
      while i < bytes.size
        c = bytes[i]
        case c
        when '"'.ord  then i = skip_string_literal(bytes, i)
        when '\''.ord then i = skip_char_or_lifetime(bytes, i)
        when 'r'.ord, 'b'.ord
          # Raw strings (`r"…"`, `r#"…"#`, `br#"…"#`) routinely embed `{`
          # / `}` — e.g. a JSON body in a `#[cfg(test)]` test — and must
          # be skipped whole or the brace matcher mis-counts depth.
          i = try_skip_raw_string(bytes, i) || i + 1
        when '/'.ord
          if i + 1 < bytes.size && bytes[i + 1] == '/'.ord
            i = skip_line_comment(bytes, i)
          elsif i + 1 < bytes.size && bytes[i + 1] == '*'.ord
            i = skip_block_comment(bytes, i)
          else
            i += 1
          end
        when '{'.ord then return i
        else              i += 1
        end
      end
      nil
    end

    private def self.find_matching_close_brace(bytes : Slice(UInt8), open_idx : Int32) : Int32?
      depth = 1
      i = open_idx + 1
      while i < bytes.size && depth > 0
        c = bytes[i]
        case c
        when '"'.ord  then i = skip_string_literal(bytes, i); next
        when '\''.ord then i = skip_char_or_lifetime(bytes, i); next
        when 'r'.ord, 'b'.ord
          if nb = try_skip_raw_string(bytes, i)
            i = nb
            next
          end
        when '/'.ord
          if i + 1 < bytes.size && bytes[i + 1] == '/'.ord
            i = skip_line_comment(bytes, i); next
          elsif i + 1 < bytes.size && bytes[i + 1] == '*'.ord
            i = skip_block_comment(bytes, i); next
          end
        when '{'.ord then depth += 1
        when '}'.ord then depth -= 1
        end
        i += 1
      end
      depth == 0 ? i - 1 : nil
    end

    # If `from` begins a Rust raw string literal — `r"…"`, `r#"…"#`,
    # `r##"…"##`, or the byte-string `br"…"` / `br#"…"#` forms — return
    # the index just past its terminator; otherwise `nil`. The closer is
    # a `"` followed by exactly the same number of `#` as the opener, so
    # interior quotes and braces are consumed verbatim. In valid Rust an
    # `r` / `br` immediately followed by `#`* `"` is unambiguously a raw
    # string (a bare `r#ident` raw identifier has no quote), so ordinary
    # identifiers and byte/binary literals (`b'x'`, `b"x"`, `0b10`) fall
    # through to `nil`.
    private def self.try_skip_raw_string(bytes : Slice(UInt8), from : Int32) : Int32?
      i = from
      if bytes[i] == 'b'.ord
        i += 1
        return unless i < bytes.size && bytes[i] == 'r'.ord
      end
      return unless i < bytes.size && bytes[i] == 'r'.ord
      i += 1
      hashes = 0
      while i < bytes.size && bytes[i] == '#'.ord
        hashes += 1
        i += 1
      end
      return unless i < bytes.size && bytes[i] == '"'.ord
      i += 1
      while i < bytes.size
        if bytes[i] == '"'.ord
          j = i + 1
          k = 0
          while k < hashes && j < bytes.size && bytes[j] == '#'.ord
            k += 1
            j += 1
          end
          return j if k == hashes
        end
        i += 1
      end
      bytes.size
    end

    private def self.skip_string_literal(bytes : Slice(UInt8), from : Int32) : Int32
      i = from + 1
      while i < bytes.size
        c = bytes[i]
        if c == '\\'.ord
          i += 2
          next
        end
        return i + 1 if c == '"'.ord
        i += 1
      end
      i
    end

    private def self.skip_char_or_lifetime(bytes : Slice(UInt8), from : Int32) : Int32
      if from + 2 < bytes.size && bytes[from + 2] == '\''.ord
        return from + 3
      end
      if from + 1 < bytes.size && bytes[from + 1] == '\\'.ord
        i = from + 2
        while i < bytes.size
          c = bytes[i]
          if c == '\\'.ord
            i += 2
            next
          end
          return i + 1 if c == '\''.ord
          i += 1
        end
        return i
      end
      from + 1
    end

    private def self.skip_line_comment(bytes : Slice(UInt8), from : Int32) : Int32
      i = from
      while i < bytes.size && bytes[i] != '\n'.ord
        i += 1
      end
      i
    end

    private def self.skip_block_comment(bytes : Slice(UInt8), from : Int32) : Int32
      i = from + 2
      while i + 1 < bytes.size
        return i + 2 if bytes[i] == '*'.ord && bytes[i + 1] == '/'.ord
        i += 1
      end
      bytes.size
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
