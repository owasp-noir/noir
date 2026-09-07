require "../../../models/detector"

module Detector::Python
  class HttpServer < Detector
    detector_for "python_http_server", extensions: %w[.py]

    # The stdlib module has to be imported before any of its handler or
    # server classes can be named, so anchor on the import the way the
    # other built-in-server detectors do (`java_httpserver` requires
    # `com.sun.net.httpserver`, `dart_http` requires `import 'dart:io'`).
    #
    # This replaces four bare substring probes — `"http.server"`,
    # `"HTTPServer"`, `"BaseHTTPRequestHandler"`, `"SimpleHTTPRequestHandler"`
    # — that matched anywhere in a file, including prose. Two real cases fell
    # out of that:
    #
    #   * a `python -m http.server` line in a comment or module docstring
    #     (the standard way to say "serve these fixtures locally") flagged
    #     the whole project as a stdlib-server app;
    #   * `HTTPServer` alone also matched Tornado's
    #     `from tornado.httpserver import HTTPServer`, so every Tornado
    #     project was additionally reported as `python_http_server` and paid
    #     for a second analyzer pass over the same tree.
    #
    # Covers `from http.server import ...`, `import [os, ]http.server[ as x]`
    # and `from http import [cookies, ]server`. `\x{FEFF}` after the line
    # start keeps a UTF-8-BOM file's first line matchable — `Noir::TextFile`
    # deliberately strips no BOM.
    IMPORT_RE = /(?:^|\n)[ \t\x{FEFF}]*(?:from[ \t]+http\.server[ \t]+import\b|import[ \t]+(?:[\w.]+[ \t]*,[ \t]*)*http\.server\b|from[ \t]+http[ \t]+import[ \t]+(?:[\w,][\w, \t]*[ \t,])?server\b)/

    # A handler subclass still counts on its own: a module that receives the
    # base class through a re-export (`from .compat import
    # BaseHTTPRequestHandler`) carries no `http.server` import of its own,
    # and it is the file the analyzer needs. Anchored to a real `class ...(`
    # header so a bare mention of the name in prose no longer qualifies.
    # Earlier bases are allowed: `class Handler(ThreadingMixIn,
    # BaseHTTPRequestHandler)` is the idiomatic way to write exactly the
    # module this branch exists for.
    HANDLER_SUBCLASS_RE = /\bclass\s+\w+\s*\(\s*(?:[\w.]+\s*,\s*)*(?:[\w.]+\.)?(?:Base|Simple|CGI)HTTPRequestHandler\s*[,)]/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

      # wsgiref.simple_server is related (per issue) but we intentionally do not auto-detect on it alone
      # here to avoid polluting :techs counts in framework fixtures that use wsgiref only as a test server
      # (e.g. pyramid fixture). Users can still force via similar names or future wsgi analyzer.
      content_matches?(file_contents, IMPORT_RE) ||
        content_matches?(file_contents, HANDLER_SUBCLASS_RE)
    end
  end
end
