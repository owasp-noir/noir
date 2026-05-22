require "spec"
require "../../../src/models/logger"
require "../../../src/miniparsers/micronaut_extractor_ts"

describe Noir::TreeSitterMicronautExtractor do
  it "resolves constants and concatenations in controller and method paths" do
    source = <<-JAVA
      package com.example.api;

      import io.micronaut.http.annotation.Controller;
      import io.micronaut.http.annotation.Get;

      @Controller(Api.BASE + "/books")
      public class BookController {
          private static final String STATS = "/stats";

          static final class Api {
              static final String BASE = "/api";
              static final String EXPORT = "/export";
          }

          @Get(STATS)
          public String stats() { return ""; }

          @Get(uri = Api.EXPORT)
          public String export() { return ""; }

          @Get(uris = {"/popular", Api.EXPORT + "/latest"})
          public String highlights() { return ""; }
      }
      JAVA

    routes = Noir::TreeSitterMicronautExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.method_name} }.should eq([
      {"GET", "/api/books/stats", "stats"},
      {"GET", "/api/books/export", "export"},
      {"GET", "/api/books/popular", "highlights"},
      {"GET", "/api/books/export/latest", "highlights"},
    ])
  end

  it "reads verb consumes/processes and keyword parameter annotation values" do
    source = <<-JAVA
      package com.example.api;

      import io.micronaut.http.MediaType;
      import io.micronaut.http.annotation.Body;
      import io.micronaut.http.annotation.Controller;
      import io.micronaut.http.annotation.Get;
      import io.micronaut.http.annotation.Header;
      import io.micronaut.http.annotation.Post;
      import io.micronaut.http.annotation.QueryValue;
      import io.micronaut.http.annotation.RequestBean;

      @Controller("/books")
      public class BookController {
          @Get(value = "/search", produces = MediaType.APPLICATION_JSON)
          public String search(@QueryValue(value = "q", defaultValue = "all") String query,
                               @Header(name = "X-Client") String client) {
              return "";
          }

          @Post(value = "/forms", consumes = MediaType.APPLICATION_FORM_URLENCODED)
          public String form(@Body Book book) {
              return "";
          }

          @Post(value = "/process", processes = MediaType.MULTIPART_FORM_DATA)
          public String process(@Body Book book) {
              return "";
          }

          @Get("/filter")
          public String filter(@RequestBean BookFilter filter) {
              return "";
          }
      }

      class Book {
          private String title;
          public void setTitle(String title) { this.title = title; }
      }

      class BookFilter {
          private String author;
          private Integer year;
          public void setAuthor(String author) { this.author = author; }
          public void setYear(Integer year) { this.year = year; }
      }
      JAVA

    dto_index = {
      "Book" => [
        Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("title", "private", true, ""),
      ],
      "BookFilter" => [
        Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("author", "private", true, ""),
        Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("year", "private", true, ""),
      ],
    } of String => Array(Noir::TreeSitterJavaParameterExtractor::FieldInfo)

    routes = Noir::TreeSitterMicronautExtractor.extract_routes(source, dto_index)
    routes.map { |r| {r.verb, r.path, r.params} }.should eq([
      {"GET", "/books/search", [
        Param.new("q", "all", "query"),
        Param.new("X-Client", "", "header"),
      ]},
      {"POST", "/books/forms", [
        Param.new("title", "", "form"),
      ]},
      {"POST", "/books/process", [
        Param.new("title", "", "form"),
      ]},
      {"GET", "/books/filter", [
        Param.new("author", "", "query"),
        Param.new("year", "", "query"),
      ]},
    ])
  end

  it "extracts annotated interface routes and controller implementations" do
    source = <<-JAVA
      package com.example.api;

      import io.micronaut.http.MediaType;
      import io.micronaut.http.annotation.Body;
      import io.micronaut.http.annotation.Controller;
      import io.micronaut.http.annotation.Get;
      import io.micronaut.http.annotation.Post;
      import io.micronaut.http.annotation.QueryValue;

      public interface CatalogApi {
          @Get("/catalog/{id}")
          String show(String id, @QueryValue("expand") String expand);

          @Post(value = "/catalog", consumes = MediaType.APPLICATION_JSON)
          String create(@Body Book book);
      }

      @Controller("/api")
      public class CatalogController implements CatalogApi {
          public String show(String id, String expand) { return ""; }
          public String create(Book book) { return ""; }
      }

      class Book {
          private String title;
          public void setTitle(String title) { this.title = title; }
      }
      JAVA

    dto_index = {
      "Book" => [
        Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("title", "private", true, ""),
      ],
    } of String => Array(Noir::TreeSitterJavaParameterExtractor::FieldInfo)

    routes = Noir::TreeSitterMicronautExtractor.extract_interface_routes(source, dto_index)
    routes["CatalogApi"].map { |r| {r.verb, r.path, r.params} }.should eq([
      {"GET", "/catalog/{id}", [
        Param.new("expand", "", "query"),
      ]},
      {"POST", "/catalog", [
        Param.new("title", "", "json"),
      ]},
    ])

    implementations = Noir::TreeSitterMicronautExtractor.extract_controller_interface_implementations(source)
    implementations.map { |impl| {impl.class_name, impl.interface_names, impl.paths} }.should eq([
      {"CatalogController", ["CatalogApi"], ["/api"]},
    ])
  end

  it "extracts ServerWebSocket endpoints with ws protocol" do
    source = <<-JAVA
      package com.example.api;

      import io.micronaut.websocket.annotation.ServerWebSocket;

      @ServerWebSocket(ChatSocket.API + "/chat/{topic}/{username}")
      public class ChatSocket {
          static final String API = "/api";
      }
      JAVA

    routes = Noir::TreeSitterMicronautExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.protocol} }.should eq([
      {"GET", "/api/chat/{topic}/{username}", "ws"},
    ])
  end
end
