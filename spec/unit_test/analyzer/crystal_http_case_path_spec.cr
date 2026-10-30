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
