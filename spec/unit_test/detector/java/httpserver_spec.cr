require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java JDK HttpServer" do
  options = create_test_options
  instance = Detector::Java::HttpServer.new options

  it "detects com.sun.net.httpserver usage with createContext" do
    content = <<-JAVA
      import com.sun.net.httpserver.HttpServer;
      import java.net.InetSocketAddress;

      public class App {
          public static void main(String[] args) throws Exception {
              HttpServer server = HttpServer.create(new InetSocketAddress(8000), 0);
              server.createContext("/", exchange -> exchange.sendResponseHeaders(200, 0));
              server.start();
          }
      }
      JAVA
    instance.detect("src/App.java", content).should be_true
  end

  it "detects fully-qualified usage without an explicit import" do
    content = <<-JAVA
      public class App {
          public static void main(String[] args) throws Exception {
              com.sun.net.httpserver.HttpServer server =
                  com.sun.net.httpserver.HttpServer.create(new java.net.InetSocketAddress(8000), 0);
              server.createContext("/api", new ApiHandler());
          }
      }
      JAVA
    instance.detect("src/App.java", content).should be_true
  end

  it "does not detect the package import without a createContext registration" do
    content = <<-JAVA
      import com.sun.net.httpserver.HttpHandler;
      import com.sun.net.httpserver.HttpExchange;

      public class LoggingHandler implements HttpHandler {
          public void handle(HttpExchange exchange) {
          }
      }
      JAVA
    instance.detect("src/LoggingHandler.java", content).should be_false
  end

  it "does not detect a framework HttpServer (Vert.x) with createContext-like calls" do
    content = <<-JAVA
      import io.vertx.core.http.HttpServer;

      public class App {
          public void start(HttpServer server) {
              server.requestHandler(req -> req.response().end("ok"));
          }
      }
      JAVA
    instance.detect("src/App.java", content).should be_false
  end

  it "does not detect non-Java files" do
    instance.detect("notes.txt", "com.sun.net.httpserver.HttpServer server; server.createContext(\"/\");").should be_false
  end
end
