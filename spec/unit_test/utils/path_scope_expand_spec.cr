require "../../spec_helper"
require "../../../src/utils/path_scope"

describe "Noir::PathScope.expand" do
  # The already-normal fast path must agree with `File.expand_path` on
  # every input, including the ones it declines.
  it "matches File.expand_path for normal and non-normal paths alike" do
    paths = [
      "/", "/a", "/a/b.py", "/a/b/", "/a//b", "/a/./b", "/a/../b", "/a/.", "/a/..",
      "/.", "/..", "/a/.hidden", "/a/..b", "/a/b..", "/a/.../b", "/a/b c/d",
      "/a/é/ü.rb", "/a/b\u0000c", String.new(Bytes[0x2f, 0x61, 0xff, 0x62]),
      "rel/a.go", "./rel", "../up", "", ".", "~/x",
    ]
    outcome = ->(block : -> String) do
      block.call
  rescue e
    e.class.name
    end
    paths.each do |path|
      outcome.call(-> { Noir::PathScope.expand(path) }).should eq(outcome.call(-> { File.expand_path(path) }))
    end
  end

  it "returns an already-normal absolute path as is" do
    path = "/srv/app/src/main.go"
    Noir::PathScope.expand(path).should be(path)
  end
end
