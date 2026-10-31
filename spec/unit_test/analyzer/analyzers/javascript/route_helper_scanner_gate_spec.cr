require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/javascript/express/route_helper_scanner"

describe Analyzer::Javascript::RouteHelperScanner do
  # The gate must never reject a file the full pattern accepts: it is the
  # full pattern with the leading receiver dropped.
  it "gates the forwarded-call pattern on a necessary condition" do
    samples = [
      "router[verb](`/api${name}`, ...middlewares, handler)",
      "app.get(path, handler)",
      "r . post ( route , h )",
      "api\n  .delete(`/v1/x`, h)",
      "x.all(p, h)",
      "$app[method](target,",
      "obj.get(key)",
      "foo.fetch(url, opts)",
      "const a = [b](c, d)",
      "nothing here",
    ]
    samples.each do |sample|
      if sample.matches?(Analyzer::Javascript::RouteHelperScanner::FORWARD_CALL_RE)
        sample.matches?(Analyzer::Javascript::RouteHelperScanner::FORWARD_CALL_GATE).should be_true
      end
    end
    "obj.get(key)".matches?(Analyzer::Javascript::RouteHelperScanner::FORWARD_CALL_GATE).should be_false
  end
end

private def index_helpers(source : String) : Analyzer::Javascript::RouteHelperScanner
  dir = File.tempname("noir-route-helper")
  Dir.mkdir_p(dir)
  file = File.join(dir, "helpers.js")
  File.write(file, source)
  scanner = Analyzer::Javascript::RouteHelperScanner.new([file], [dir], dir, NoirLogger.new(false, false, false, true))
  scanner.index
  scanner
ensure
  FileUtils.rm_rf(dir) if dir
end

# A non-ASCII bundle of `n` small functions and object literals, one module
# call and one forwarding helper, so the (deliberately bounded) function x
# forward attribution stays linear.
private def helper_bundle(n : Int32) : String
  String.build do |io|
    io << "// 한글 주석 é\nrequire('./routes')(app)\n"
    n.times do |i|
      io << "function h" << i << "(a, b) { return label(a, '✓', b) }\n"
      io << "var o" << i << " = { k: '✓' }\n"
    end
    io << "function setup(router, path, handler) { router.get(path, handler) }\n"
  end
end

describe Analyzer::Javascript::RouteHelperScanner do
  it "indexes a forwarding helper in a non-ASCII file" do
    scanner = index_helpers("// é\nconst label = '한글'\nfunction setup(router, name, handler) {\n  router.post(name, handler)\n}\n")
    specs = scanner.helpers.values.first
    specs.keys.should eq ["setup"]
    specs["setup"].forwards.first.verb.should eq "post"
  end

  # vikunja vendors a 3.5 MB non-ASCII `scalar.standalone.js`; every char
  # offset lookup per function was O(offset) there, and the file alone took
  # 8 s. Linear means 4x the input costs about 4x, not 16x.
  it "indexes a large non-ASCII file in linear time" do
    index_helpers(helper_bundle(200)).helpers.values.first.keys.should eq ["setup"]
    small = Time.measure { index_helpers(helper_bundle(1_000)) }
    large = Time.measure { index_helpers(helper_bundle(4_000)) }
    (large / small).should be < 10
  end
end
