require "../../spec_helper"
require "../../../src/models/logger"
require "../../../src/utils/file_url_scanner"

describe Noir::FileUrlScanner do
  describe ".each_url" do
    it "reports every URL on a line, not just the first" do
      urls = [] of String
      Noir::FileUrlScanner.each_url("see https://a.example/one and https://a.example/two") { |u| urls << u }
      urls.should eq ["https://a.example/one", "https://a.example/two"]
    end

    it "stops at markup rather than swallowing the closing tag" do
      urls = [] of String
      Noir::FileUrlScanner.each_url("<string>https://a.example/install</string>") { |u| urls << u }
      urls.should eq ["https://a.example/install"]
    end

    it "stops at angle-bracket delimiters" do
      urls = [] of String
      Noir::FileUrlScanner.each_url("feed at <https://a.example/rss>") { |u| urls << u }
      urls.should eq ["https://a.example/rss"]
    end

    it "drops the closing paren of a markdown link" do
      urls = [] of String
      Noir::FileUrlScanner.each_url("[donate](https://a.example/donate/).") { |u| urls << u }
      urls.should eq ["https://a.example/donate/"]
    end

    it "keeps balanced parentheses inside a URL" do
      urls = [] of String
      Noir::FileUrlScanner.each_url("https://a.example/wiki/Foo_(bar)") { |u| urls << u }
      urls.should eq ["https://a.example/wiki/Foo_(bar)"]
    end

    it "trims trailing sentence punctuation" do
      urls = [] of String
      Noir::FileUrlScanner.each_url("read https://a.example/docs, then https://a.example/faq!") { |u| urls << u }
      urls.should eq ["https://a.example/docs", "https://a.example/faq"]
    end

    it "stops at a quote so a quoted literal keeps its own bounds" do
      urls = [] of String
      Noir::FileUrlScanner.each_url(%(url = "https://a.example/api", next)) { |u| urls << u }
      urls.should eq ["https://a.example/api"]
    end

    it "rejects a candidate that is only a scheme" do
      urls = [] of String
      Noir::FileUrlScanner.each_url("https://") { |u| urls << u }
      urls.should be_empty
    end
  end

  describe ".binary_line?" do
    it "flags a line carrying binary control bytes" do
      # A protobuf/asset blob whose first 512 bytes look clean still reaches
      # the analyzers; the URL-shaped byte run inside it is not an endpoint.
      Noir::FileUrlScanner.binary_line?("https://a.example/EFCmCqQ\u0002\u0008\u0001").should be_true
    end

    it "accepts ordinary source text, including tabs" do
      Noir::FileUrlScanner.binary_line?("\turl = https://a.example/x").should be_false
    end
  end
end
