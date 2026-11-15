require "../../spec_helper"
require "../../../src/miniparsers/js_mount_prefix"

describe Noir::JSMountPrefix do
  it "reads literals and constants in full" do
    {"'/api'" => "/api", "BASE" => "/fixed", "BASE + '/v1'" => "/fixed/v1", "`${BASE}/v1`" => "/fixed/v1"}.each do |expression, expected|
      Noir::JSMountPrefix.read(expression, {"BASE" => "/fixed"}).should eq(expected)
    end
  end

  it "keeps only a final rooted tail behind unread operands" do
    unread = Noir::JSMountPrefix::UNREAD.to_s
    {
      "config.base + '/v1'"    => "#{unread}/v1",
      "base + '/v1'"           => "#{unread}/v1",
      "`${base}/items`"        => "#{unread}/items",
      "`${config.base}/items`" => "#{unread}/items",
      "getBase() + '/items'"   => "#{unread}/items",
      "process.env.API_PREFIX" => unread,
      "config.base"            => unread,
      "base"                   => unread,
      "getBase()"              => unread,
      "base + '/v1' + suffix"  => unread,
      "'/a/' + value + '/b'"   => unread,
      "base + 'relative'"      => unread,
      "`${base}/v1${suffix}`"  => unread,
      "`${base}relative`"      => unread,
    }.each do |expression, expected|
      Noir::JSMountPrefix.read(expression, {} of String => String).should eq(expected)
    end
    Noir::JSMountPrefix.read("built + '/tail'", {} of String => String, "const built = '/a/' + runtime;").should eq(unread)
  end

  it "preserves a previously emitted template path when URL replacement is disallowed" do
    result = Noir::JSMountPrefix.read("`${base}/items`", {} of String => String, "", "/${base}/items")
    endpoint = Noir::JSMountPrefix.finish(Endpoint.new(result, "GET"))
    endpoint.url.should eq("/${base}/items")
    endpoint.resolution.should eq({"prefix" => "unresolved"})
  end

  it "composes marks on either side without exposing its carrier" do
    unread = Noir::JSMountPrefix::UNREAD.to_s
    path = Noir::JSMountPrefix.join("/api", "#{unread}/v1")
    path = Noir::JSMountPrefix.join(path, "#{unread}/items")
    endpoint = Noir::JSMountPrefix.finish(Endpoint.new(path, "GET"))
    endpoint.url.should eq("/api/v1/items")
    endpoint.resolution.should eq({"prefix" => "unresolved"})
    endpoint.to_json.should_not contain(unread)
    endpoint.to_yaml.should_not contain(unread)
  end
end
