require "../../models/analyzer"

module Analyzer::Swift
  abstract class SwiftEngine < Analyzer
    def analyze
      parallel_file_scan do |path|
        result.concat(analyze_file(path))
      end
      result
    end

    abstract def analyze_file(path : String) : Array(Endpoint)

    # `Tests/...` directory + `*Tests.swift` filename: the rigid Swift
    # Package Manager / XCTest conventions for test sources.
    def self.swift_test_path?(path : String) : Bool
      return true if path.includes?("/Tests/")
      File.basename(path).ends_with?("Tests.swift")
    end

    private def swift_test_path?(path : String) : Bool
      SwiftEngine.swift_test_path?(path)
    end

    # SwiftPM parks resolved dependency sources under `.build/` (and Xcode
    # under `.swiftpm/`). Scanning them pulls every transitive package's
    # routes into the report — pure noise against the project under test.
    def self.swift_vendor_path?(path : String) : Bool
      path.includes?("/.build/") || path.starts_with?(".build/") ||
        path.includes?("/.swiftpm/") || path.starts_with?(".swiftpm/")
    end

    private def swift_vendor_path?(path : String) : Bool
      SwiftEngine.swift_vendor_path?(path)
    end

    # `.swift` extension filter baked in. Subclasses that need a custom
    # scan shape can override `analyze` and call this helper directly.
    protected def parallel_file_scan(&block : String -> Nil) : Nil
      begin
        parallel_analyze(all_files) do |path|
          next if File.directory?(path)
          next unless File.exists?(path) && File.extname(path) == ".swift"
          # Swift Package Manager convention parks tests under
          # `Tests/<TargetName>Tests/`. Real route handlers never
          # live there, but vapor's own repo accounts for ~58
          # phantom endpoints from `Tests/VaporTests/*Tests.swift`
          # files that register routes against an inline test app.
          # XCTest-style `*Tests.swift` filenames carry the same
          # signal — pick them both up.
          next if swift_test_path?(path)
          next if swift_vendor_path?(path)

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
