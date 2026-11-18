require "file_utils"
require "../../spec_helper"
require "../../../src/analyzer/analyzers/crystal/http.cr"

describe "crystal_http case request.path" do
  it "reads a path switch whose value is assigned or returned" do
    temp_dir = File.tempname("crystal_http_case")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "server.cr")
    File.write(temp_file, <<-CRYSTAL)
      server = HTTP::Server.new do |ctx|
        body = case ctx.request.path
               when "/hello"
                 if ctx.request.method == "HEAD"
                   ""
                 end
               when "/items"
                 "items"
               end
        ctx.response.print body
      end

      def route(ctx)
        return case ctx.request.path
        when "/returned"
          "r"
        end
      end

      kind = case status
             when "/not-a-route"
               "x"
             end
      CRYSTAL

    endpoints = Analyzer::Crystal::Http.new(create_test_options).analyze_file(temp_file)
    endpoints.map(&.url).should eq(["/hello", "/items", "/returned"])
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  it "closes an assigned or one-line case at its own end" do
    temp_dir = File.tempname("crystal_http_case_close")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "server.cr")
    File.write(temp_file, <<-CRYSTAL)
      server = HTTP::Server.new do |ctx|
        body = case ctx.request.path
               when "/hello"
                 "Hello"
               end
        asset = case File.extname(name)
                when "/static-not-route"
                  "x"
                end
        x = case ctx.request.path when "/oneline" then "a" else "b" end
        y = case kind when "/after-oneline" then 1 end
        ctx.response.print(case ctx.request.path
                           when "/arg"
                             "a"
                           end)
        z = case kind
            when "/after-arg"
              1
            end
      end
      CRYSTAL

    endpoints = Analyzer::Crystal::Http.new(create_test_options).analyze_file(temp_file)
    endpoints.map(&.url).should eq(["/hello", "/oneline", "/arg"])
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end
end

describe "crystal_http handler argument name" do
  it "reads routes and params on whatever the handler names its argument" do
    temp_dir = File.tempname("crystal_http_arg")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "server.cr")
    File.write(temp_file, <<-CRYSTAL)
      server = HTTP::Server.new do |ctx|
        if ctx.request.method == "POST" && ctx.request.path == "/items"
          token = ctx.request.headers["X-Token"]
        elsif ctx.request.path == "/orders"
          page = ctx.request.query_params["page"]
        end
      end

      class Health
        include HTTP::Handler

        def call(context : HTTP::Server::Context)
          c = context
          return call_next(c) unless c.request.path.starts_with?("/api/")
          if c.request.path == "/ready"
            "ok"
          end
        end
      end

      def guard(env : HTTP::Server::Context)
        raise "no" if env.request.path == "/not-a-route"
      end
      CRYSTAL

    endpoints = Analyzer::Crystal::Http.new(create_test_options).analyze_file(temp_file)
    endpoints.map { |e| "#{e.method} #{e.url}" }.should eq(["POST /items", "GET /orders", "GET /ready"])
    endpoints[0].params.map(&.name).should eq(["X-Token"])
    endpoints[1].params.map(&.name).should eq(["page"])
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end
end
