require "../../src/analyzer/analyzers/analyzer_go_echo.cr"
require "../../src/options"

describe "analyzer_go_echo" do
  options = default_options()
  instance = AnalyzerGoEcho.new(options)

  it "instance.get_route_path_go_echo - GET" do
    instance.get_route_path_go_echo("e.GET(\"/\", func(c echo.Context) error {").should eq("/")
  end
  it "instance.get_route_path_go_echo - POST" do
    instance.get_route_path_go_echo("e.POST(\"/\", func(c echo.Context) error {").should eq("/")
  end
  it "instance.get_route_path_go_echo - PUT" do
    instance.get_route_path_go_echo("e.PUT(\"/\", func(c echo.Context) error {").should eq("/")
  end
  it "instance.get_route_path_go_echo - DELETE" do
    instance.get_route_path_go_echo("e.DELETE(\"/\", func(c echo.Context) error {").should eq("/")
  end
  it "instance.get_route_path_go_echo - PATCH" do
    instance.get_route_path_go_echo("e.PATCH(\"/\", func(c echo.Context) error {").should eq("/")
  end
  it "instance.get_route_path_go_echo - HEAD" do
    instance.get_route_path_go_echo("e.HEAD(\"/\", func(c echo.Context) error {").should eq("/")
  end
  it "instance.get_route_path_go_echo - OPTIONS" do
    instance.get_route_path_go_echo("e.OPTIONS(\"/\", func(c echo.Context) error {").should eq("/")
  end
  it "instance.get_route_path_go_echo - customContext1" do
    instance.get_route_path_go_echo("customEnv.OPTIONS(\"/\", func(c echo.Context) error {").should eq("/")
  end
  it "instance.get_route_path_go_echo - customContext2" do
    instance.get_route_path_go_echo("customEnv.OPTIONS(\"/\", func(myContext echo.Context) error {").should eq("/")
  end
end
