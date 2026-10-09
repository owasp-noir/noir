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

    it "trims interleaved punctuation and unbalanced closers" do
      Noir::FileUrlScanner.trim("https://a.example/x_(y).).]").should eq "https://a.example/x_(y)"
      Noir::FileUrlScanner.trim("https://a.example/é).").should eq "https://a.example/é"
    end

    # Each trimmed byte used to recount the brackets over the whole URL.
    it "trims a long run of closers in linear time" do
      raw = "http://example.com/x" + ")" * 20000
      result = nil
      elapsed = Time.measure { result = Noir::FileUrlScanner.trim(raw) }

      result.should eq "http://example.com/x"
      elapsed.should be < 2.seconds
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

    it "rejects candidates whose parsed HTTP(S) host is empty" do
      candidates = [
        "https:///path",
        "https://?next=https://target.example/path",
        "https://#fragment",
        "https://:443/path",
        "https://user@:443/path",
      ]

      urls = [] of String
      candidates.each do |candidate|
        Noir::FileUrlScanner.each_url(candidate) { |url| urls << url }
      end
      urls.should be_empty
    end

    it "keeps candidates with a domain or IPv6 host" do
      urls = [] of String
      text = [
        "https://target.example/path",
        "https://[::1]/path",
        "https://api.example/users/{id}",
      ].join(" ")
      Noir::FileUrlScanner.each_url(text) { |url| urls << url }
      urls.should eq [
        "https://target.example/path",
        "https://[::1]/path",
        "https://api.example/users/{id}",
      ]
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

  describe ".path_under_base" do
    under = ->(candidate : String, base : String) {
      Noir::FileUrlScanner.path_under_base(URI.parse(candidate), Noir::FileUrlScanner::BaseUrl.parse(base))
    }

    it "returns the path relative to a base that carries a path" do
      # The optimizer prefixes `-u` again, so the full `/api/users` came out
      # as `http://example.com/api/api/users`.
      under.call("http://example.com/api/users", "http://example.com/api").should eq("/users")
      under.call("http://example.com/api/users", "http://example.com/api/").should eq("/users")
    end

    it "returns the full path under a root base" do
      under.call("http://example.com/api/users", "http://example.com").should eq("/api/users")
      under.call("http://example.com/", "http://example.com").should eq("/")
    end

    it "returns an empty path for the base itself" do
      under.call("http://example.com/api", "http://example.com/api").should eq("")
    end

    it "rejects hosts that merely start with the base host" do
      under.call("http://example.com.attacker.net/steal", "http://example.com").should be_nil
      under.call("http://example.community/other", "http://example.com").should be_nil
    end

    it "rejects a sibling path that only shares the base path as a prefix" do
      under.call("http://h/apiv2/x", "http://h/api").should be_nil
    end

    it "compares scheme and port as origins" do
      under.call("https://example.com/x", "http://example.com").should be_nil
      under.call("http://example.com:8080/x", "http://example.com").should be_nil
      under.call("http://example.com:80/x", "http://example.com").should eq("/x")
      under.call("HTTP://EXAMPLE.com/x", "http://example.com").should eq("/x")
    end

    it "does not match a base that appears only in the query" do
      under.call("http://other.test/proxy?next=http://example.com/x", "http://example.com").should be_nil
    end
  end
end
