require "../../models/analyzer"

require "./file_scan_engine"

module Analyzer::Swift
  abstract class SwiftEngine < FileScanEngine
    # `Tests/...` directory + `*Tests.swift` filename: the rigid Swift
    # Package Manager / XCTest conventions for test sources.
    #
    # Both take the scan-base-relative path (`Analyzer#base_relative_path`),
    # never the absolute one — SwiftPM's layout is relative to the package,
    # and matching the absolute path made the scan's answer depend on where
    # the package happened to be checked out.
    def self.swift_test_path?(relative_path : String) : Bool
      return true if relative_path.includes?("/Tests/")
      File.basename(relative_path).ends_with?("Tests.swift")
    end

    private def swift_test_path?(path : String) : Bool
      SwiftEngine.swift_test_path?(base_relative_path(path))
    end

    # SwiftPM parks resolved dependency sources under `.build/` (and Xcode
    # under `.swiftpm/`). Scanning them pulls every transitive package's
    # routes into the report — pure noise against the project under test.
    def self.swift_vendor_path?(relative_path : String) : Bool
      relative_path.includes?("/.build/") || relative_path.includes?("/.swiftpm/")
    end

    private def swift_vendor_path?(path : String) : Bool
      SwiftEngine.swift_vendor_path?(base_relative_path(path))
    end

    # `.swift` sources from the extension index. Subclasses that need a
    # custom scan shape can override `analyze` and call this helper
    # directly. Paths are detector-registered regular files — no per-path
    # `File.exists?` / `File.directory?`.
    protected def scan_target_files : Array(String)
      get_files_by_extension(".swift")
    end

    protected def scan_accepts?(path : String) : Bool
      # Swift Package Manager convention parks tests under
      # `Tests/<TargetName>Tests/`. Real route handlers never
      # live there, but vapor's own repo accounts for ~58
      # phantom endpoints from `Tests/VaporTests/*Tests.swift`
      # files that register routes against an inline test app.
      # XCTest-style `*Tests.swift` filenames carry the same
      # signal — pick them both up.
      return false if swift_test_path?(path)
      !swift_vendor_path?(path)
    end
  end
end
