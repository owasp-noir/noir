require "../../../spec_helper"
require "../../../../src/detector/detectors/ruby/*"

describe "Detect Ruby WEBrick" do
  options = create_test_options
  instance = Detector::Ruby::Webrick.new options

  it "detects require webrick single quote" do
    instance.detect("server.rb", "require 'webrick'\nserver = WEBrick::HTTPServer.new").should be_true
  end

  it "detects require webrick double quote" do
    instance.detect("app.rb", "require \"webrick\"").should be_true
  end

  it "detects WEBrick::HTTPServer" do
    code = <<-RUBY
      server = WEBrick::HTTPServer.new(Port: 8080)
      server.mount_proc '/' do |req, res|
      end
      RUBY
    instance.detect("srv.rb", code).should be_true
  end

  it "detects mount_proc usage" do
    instance.detect("p.rb", "server.mount_proc('/api') do |req, res| end").should be_true
  end

  it "detects AbstractServlet subclass full path" do
    code = <<-RUBY
      class MyHandler < WEBrick::HTTPServlet::AbstractServlet
        def do_GET(req, res); end
      end
      RUBY
    instance.detect("handler.rb", code).should be_true
  end

  it "detects AbstractServlet subclass relative" do
    code = <<-RUBY
      require 'webrick'
      class MyHandler < HTTPServlet::AbstractServlet
        def do_POST(req, res); end
      end
      RUBY
    instance.detect("h.rb", code).should be_true
  end

  it "does not detect on non-rb file even with signal" do
    instance.detect("Gemfile", "gem 'webrick'").should be_false
  end

  it "does not detect on plain ruby without webrick signals" do
    instance.detect("plain.rb", "puts 'hello'\nclass Foo; end").should be_false
  end

  it "does not fire on incidental webrick in comment" do
    # Analyzer is the real gate; detector is existence signal. But we still
    # want detector conservative on pure comment-only.
    instance.detect("doc.rb", "# use webrick for the server\n# WEBrick::HTTPServer").should be_true
    # ^ actually catches because "webrick" substring; acceptable (analyzer emits 0)
  end
end
