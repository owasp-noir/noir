require "file_utils"
require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/javascript/socketio"
require "../../../src/tagger/tagger"

# One file registering thousands of `prefix + "x"` events, each calling the
# same login check. The prefix lookup used to rescan the file per event and
# the auth tagger walked to each event's line from the top: 16k events took
# ~25s. Both are per-file now, so 4x the events must cost about 4x the time.
private def timed_scan(events : Int32) : Tuple(Array(Endpoint), Time::Span)
  temp_dir = File.tempname("socketio_scaling")
  CodeLocator.instance.clear_all
  source = String.build do |io|
    io << "const { Server } = require(\"socket.io\");\nconst io = new Server(3000);\n"
    io << "const p = \"pre_\";\n"
    io << "function checkLogin(socket) {\n  if (!socket.userID) throw new Error(\"no\");\n}\n"
    io << "io.on(\"connection\", (socket) => {\n"
    events.times { |i| io << "  socket.on(p + \"e#{i}\", async (d, cb) => { checkLogin(socket); cb(); });\n" }
    io << "});\n"
  end
  path = File.join(temp_dir, "server.js")
  Dir.mkdir_p(temp_dir)
  File.write(path, source)
  CodeLocator.instance.register_file(path, source)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
  endpoints = [] of Endpoint
  elapsed = Time.measure do
    endpoints = Analyzer::Javascript::SocketIO.new(options).analyze
    SocketIOAuthTagger.new(options).perform(endpoints)
  end
  {endpoints, elapsed}
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(temp_dir) if temp_dir
end

describe "Socket.IO large-file scaling" do
  it "resolves prefixed events and their check in linear time" do
    small, small_time = timed_scan(2000)
    large, large_time = timed_scan(8000)
    small.size.should eq(2000)
    large.size.should eq(8000)
    large.last.url.should eq("ws://pre_e7999")
    large.last.tags.map(&.name).should eq(["auth"])
    # Linear is ~4x; the quadratic walks were ~16x.
    (large_time / {small_time, 1.millisecond}.max).should be < 9.0
  end
end
