require "../../../models/detector"

module Detector::Java
  class HttpServer < Detector
    detector_for "java_httpserver", extensions: %w[.java]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      # JDK built-in HTTP server. The `com.sun.net.httpserver` package
      # qualifier discriminates it from framework `HttpServer` types
      # (e.g. Vert.x `io.vertx.core.http.HttpServer`); pair it with an
      # actual `createContext(...)` registration so files that merely
      # reference the package (filters, handler-only classes) don't
      # trip the analyzer with nothing to extract.
      return false unless file_contents.includes?("com.sun.net.httpserver")
      file_contents.includes?("createContext")
    end
  end
end
