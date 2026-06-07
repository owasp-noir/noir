require "../../../utils/path_scope"

module Analyzer::Dart
  # Shared helpers for the Dart framework analyzers (Dart Frog, Shelf,
  # Serverpod). Kept framework-agnostic so each analyzer can opt in
  # without duplicating path/string conventions.
  module Helper
    extend self

    # Standard Dart test-file conventions. The Dart tooling discovers
    # tests under a project-root `test/` directory and via the
    # `*_test.dart` suffix; neither ever serves real traffic. Dart Frog
    # in particular mirrors the route tree under `test/routes/`, so a
    # naive `/routes/` match would surface every mock handler as a live
    # endpoint. Centralized so every Dart analyzer can opt in via
    # `next if Helper.test_path?(path, base_paths)`.
    #
    #   * `/test/`, `test/` — Dart's `dart test` discovery root and the
    #                         Dart Frog `test/routes/` mirror tree
    #   * `*_test.dart`     — the canonical Dart unit-test suffix
    def test_path?(path : String, base_path : String? = nil) : Bool
      relative = relative_for_match(path, base_path)
      return true if relative.includes?("/test/")
      return true if relative.starts_with?("test/")
      File.basename(path).ends_with?("_test.dart")
    end

    def test_path?(path : String, base_paths : Array(String)) : Bool
      test_path?(path, base_path_for(path, base_paths))
    end

    # Replace `//` line and `/* */` block comments with spaces, leaving
    # string literals and overall byte offsets intact so downstream
    # regex/offset logic still lines up with the original source.
    def strip_comments(text : String) : String
      result = String::Builder.new
      chars = text.chars
      i = 0
      in_string = false
      string_quote = '\0'

      while i < chars.size
        c = chars[i]

        if in_string
          if c == '\\' && i + 1 < chars.size
            result << c
            result << chars[i + 1]
            i += 2
            next
          end
          in_string = false if c == string_quote
          result << c
          i += 1
          next
        end

        if c == '"' || c == '\''
          in_string = true
          string_quote = c
          result << c
          i += 1
          next
        end

        if c == '/' && i + 1 < chars.size && chars[i + 1] == '/'
          while i < chars.size && chars[i] != '\n'
            result << ' '
            i += 1
          end
          next
        end

        if c == '/' && i + 1 < chars.size && chars[i + 1] == '*'
          result << "  "
          i += 2
          while i + 1 < chars.size && !(chars[i] == '*' && chars[i + 1] == '/')
            result << (chars[i] == '\n' ? '\n' : ' ')
            i += 1
          end
          if i + 1 < chars.size
            result << "  "
            i += 2
          end
          next
        end

        result << c
        i += 1
      end

      result.to_s
    end

    # Pull the contents of a leading single/double-quoted string literal
    # from an argument expression, honouring backslash escapes. Returns
    # nil when the expression doesn't start with a string literal.
    def extract_string_literal(text : String) : String?
      stripped = text.strip
      return if stripped.empty?
      quote = stripped[0]
      return unless quote == '"' || quote == '\''
      i = 1
      while i < stripped.size
        c = stripped[i]
        if c == '\\' && i + 1 < stripped.size
          i += 2
          next
        end
        return stripped[1...i] if c == quote
        i += 1
      end
      nil
    end

    private def relative_for_match(path : String, base_path : String?) : String
      Noir::PathScope.relative_under(path, base_path)
    end

    private def base_path_for(path : String, base_paths : Array(String)) : String?
      Noir::PathScope.longest_base(path, base_paths)
    end
  end
end
