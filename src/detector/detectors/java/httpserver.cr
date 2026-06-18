require "../../../models/detector"

module Detector::Java
  class HttpServer < Detector
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

    def applicable?(filename : String) : Bool
      filename.ends_with?(".java")
    end

    def set_name
      @name = "java_httpserver"
    end
  end
end
