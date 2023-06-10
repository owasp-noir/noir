require "../../src/analyzer/analyzers/analyzer_go_echo.cr"

describe "analyzer_go_echo" do
  it "get_route_path_go_echo - GET" do
    get_route_path_go_echo("e.GET(\"/\", func(c echo.Context) error {").should eq("/")
  end
  it "get_route_path_go_echo - POST" do
    get_route_path_go_echo("e.POST(\"/\", func(c echo.Context) error {").should eq("/")
  end
  it "get_route_path_go_echo - PUT" do
    get_route_path_go_echo("e.PUT(\"/\", func(c echo.Context) error {").should eq("/")
  end
  it "get_route_path_go_echo - DELETE" do
    get_route_path_go_echo("e.DELETE(\"/\", func(c echo.Context) error {").should eq("/")
  end
  it "get_route_path_go_echo - PATCH" do
    get_route_path_go_echo("e.PATCH(\"/\", func(c echo.Context) error {").should eq("/")
  end
  it "get_route_path_go_echo - HEAD" do
    get_route_path_go_echo("e.HEAD(\"/\", func(c echo.Context) error {").should eq("/")
  end
  it "get_route_path_go_echo - OPTIONS" do
    get_route_path_go_echo("e.OPTIONS(\"/\", func(c echo.Context) error {").should eq("/")
  end
end
