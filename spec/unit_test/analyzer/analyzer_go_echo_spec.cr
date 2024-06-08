require "../../../src/analyzer/analyzers/analyzer_go_echo.cr"
require "../../../src/options"

describe "analyzer_go_echo" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = AnalyzerGoEcho.new(options)
  groups = [] of Hash(String, String)

  it "instance.get_route_path - GET" do
    instance.get_route_path("e.GET(\"/\", func(c echo.Context) error {", groups).should eq("/")
  end
  it "instance.get_route_path - POST" do
    instance.get_route_path("e.POST(\"/\", func(c echo.Context) error {", groups).should eq("/")
  end
  it "instance.get_route_path - PUT" do
    instance.get_route_path("e.PUT(\"/\", func(c echo.Context) error {", groups).should eq("/")
  end
  it "instance.get_route_path - DELETE" do
    instance.get_route_path("e.DELETE(\"/\", func(c echo.Context) error {", groups).should eq("/")
  end
  it "instance.get_route_path - PATCH" do
    instance.get_route_path("e.PATCH(\"/\", func(c echo.Context) error {", groups).should eq("/")
  end
  it "instance.get_route_path - HEAD" do
    instance.get_route_path("e.HEAD(\"/\", func(c echo.Context) error {", groups).should eq("/")
  end
  it "instance.get_route_path - OPTIONS" do
    instance.get_route_path("e.OPTIONS(\"/\", func(c echo.Context) error {", groups).should eq("/")
  end
  it "instance.get_route_path - customContext1" do
    instance.get_route_path("customEnv.OPTIONS(\"/\", func(c echo.Context) error {", groups).should eq("/")
  end
  it "instance.get_route_path - customContext2" do
    instance.get_route_path("customEnv.OPTIONS(\"/\", func(myContext echo.Context) error {", groups).should eq("/")
  end

  it "instance.get_static_path - Static" do
    rtn = {
      "static_path" => "/",
      "file_path"   => "public",
    }
    instance.get_static_path("e.Static(\"/\", \"public\")").should eq(rtn)
  end

  it "instance.get_static_path - Static" do
    rtn = {
      "static_path" => "/abcd",
      "file_path"   => "./public",
    }
    instance.get_static_path("e.Static(\"/abcd\", \"./public\")").should eq(rtn)
  end
end
