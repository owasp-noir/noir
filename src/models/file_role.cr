require "../utils/text_file"

module Noir
  # A role describes a file under the conventions selected by its consumer.
  # A CLI analyzer and a framework analyzer can select different conventions
  # for the same language. A file matching none stays in the report.
  module FileRole
    enum Role
      Production
      Test
      Example
      Vendored
      Generated
    end

    # Match either location pattern. A content pattern additionally requires
    # decoded source from TextFile, and missing content leaves the rule unmatched.
    struct Convention
      getter role : Role

      def initialize(@role : Role, *, @path : Regex? = nil, @name : Regex? = nil, @lowercase_path : Bool = false, @content : Regex? = nil)
      end

      def matches?(relative_path : String, filename : String, content : String?) : Bool
        return false unless location_matches?(relative_path, filename)
        if pattern = @content
          return false unless content
          return pattern.matches?(content, options: TextFile::MATCH_OPTIONS)
        end
        true
      end

      private def location_matches?(relative_path : String, filename : String) : Bool
        if pattern = @path
          path = @lowercase_path ? relative_path.downcase : relative_path
          return true if path.matches?(pattern)
        end
        if pattern = @name
          return File.basename(filename).matches?(pattern)
        end
        false
      end
    end

    # The caller supplies the path relative to the owning scan base, in the
    # same rooted or unrooted form its conventions use. The first match wins.
    def self.classify(relative_path : String, *conventions : Convention, filename : String = relative_path, content : String? = nil) : Role
      conventions.each do |convention|
        return convention.role if convention.matches?(relative_path, filename, content)
      end
      Role::Production
    end

    # Analyzer keeps its cached multi-base lookup. Pass the original filename
    # too, for consumers whose name and directory gates use separate inputs.
    module Scoped
      protected def file_role(path : String, *conventions : Convention) : Role
        FileRole.classify(base_relative_path(path), *conventions, filename: path)
      end
    end

    # Shared only by callers with identical conventions, including case rules.
    CARGO_HARNESSES        = Convention.new(:test, path: Regex.union("/tests/", "/benches/"))
    CLI_TEST               = Convention.new(:test, path: Regex.union("/test/", "_test."), lowercase_path: true)
    CLI_SPEC               = Convention.new(:test, path: Regex.union("/test/", "_spec."), lowercase_path: true)
    TYPESCRIPT_ROUTER_TEST = Convention.new(:test, path: Regex.union(
      "/test/", "/tests/", "/__tests__/", "/e2e/", "/snapshots/", "/test-files/", ".test.", ".spec."
    ))
  end
end
