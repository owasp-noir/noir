require "../../spec_helper"
require "../../../src/analyzer/analyzers/go/goyave.cr"

describe "analyzer_go_goyave" do
  options = create_test_options
  instance = Analyzer::Go::Goyave.new(options)
  groups = [] of Hash(String, String)

  it "instance.get_route_path - GET" do
    instance.get_route_path("router.Get(\"/\", handler)", groups).should eq("/")
  end
  it "instance.get_route_path - POST" do
    instance.get_route_path("router.Post(\"/\", handler)", groups).should eq("/")
  end
  it "instance.get_route_path - PUT" do
    instance.get_route_path("router.Put(\"/\", handler)", groups).should eq("/")
  end
  it "instance.get_route_path - DELETE" do
    instance.get_route_path("router.Delete(\"/\", handler)", groups).should eq("/")
  end
  it "instance.get_route_path - PATCH" do
    instance.get_route_path("router.Patch(\"/\", handler)", groups).should eq("/")
  end
  it "instance.get_route_path - OPTIONS" do
    instance.get_route_path("router.Options(\"/\", handler)", groups).should eq("/")
  end

  it "instance.get_route_path - With Group" do
    g = [{"router" => "/api"}]
    instance.get_route_path("router.Get(\"/users\", handler)", g).should eq("/api/users")
  end

  it "instance.get_route_path - With Subrouter" do
    g = [{"sub" => "/api"}]
    instance.get_route_path("sub.Get(\"/users\", handler)", g).should eq("/api/users")
  end

  it "instance.get_static_path - Static" do
    rtn = {
      "static_path" => "/static",
      "file_path"   => "",
    }
    instance.get_static_path("router.Static(&osfs.FS{}, \"/static\", false)").should eq(rtn)
  end
end
