require "./file_scan_engine"
require "../../miniparsers/c_http_support"

# Base for the C embedded HTTP server analyzers (Mongoose, CivetWeb,
# libmicrohttpd): every C/C++ source except the libraries' own vendored
# sources, one file at a time.
abstract class CEngine < FileScanEngine
  # C apps embed these libraries from C++ too (CivetWeb ships a C++ wrapper).
  EXTENSIONS = %w[.c .h .cc .cpp .cxx .hpp]
  # The libraries' own sources, vendored next to the app as the amalgamated
  # file or as a whole checkout (`third_party/civetweb/src/civetweb.c`,
  # `lib/libmicrohttpd-1.0.1/doc/examples/`, its tests).
  VENDORED     = Set{"mongoose.c", "mongoose.h", "civetweb.c", "civetweb.h", "CivetServer.cpp", "CivetServer.h", "microhttpd.h"}
  VENDORED_DIR = %r{(?:\A|/)(?:mongoose|civetweb|libmicrohttpd)[\w.\-]*/(?:src|examples|tutorials|test|unittest|fuzztest|doc)/}
  # A whole `test`/`tests`/`unittest(s)` directory segment: the mock servers a
  # unit test starts on localhost (`svr.Get("/accept_ok", ...)`, a `CROW_ROUTE`
  # on a throwaway `SimpleApp`), never routes the application serves.
  TEST_DIR = %r{/(?:tests?|unit_?tests?)/}i

  # Takes the scan-base-relative path (`Analyzer#base_relative_path`, rooted
  # with a leading `/`), never the absolute one: a `tests/` directory above
  # the scan base is not this project's test tree, and `-b path/to/tests`
  # still reports its routes. Shared with the cpp_* route analyzers, which
  # are plain `Analyzer`s and don't go through `scan_accepts?`.
  def self.test_path?(relative_path : String) : Bool
    relative_path.matches?(TEST_DIR)
  end

  protected def scan_target_files : Array(String)
    get_files_by_extensions(EXTENSIONS)
  end

  protected def scan_accepts?(path : String) : Bool
    relative = base_relative_path(path)
    !VENDORED.includes?(File.basename(relative)) && !relative.matches?(VENDORED_DIR) && !CEngine.test_path?(relative)
  end
end
