require "../../spec_helper"
require "../../../src/miniparsers/go_named_handler"

private def claimed_rows(source : String) : Array(Int32)
  routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
  named = Noir::GoNamedHandler.new(source, "main.go", routes)
  rows = [] of Int32
  source.lines.each_with_index { |line, i| rows << i if named.claim?(i, line) }
  rows
end

describe Noir::GoNamedHandler do
  it "parses plain handler references only" do
    Noir::GoNamedHandler.reference("listA").should eq({"", "listA"})
    Noir::GoNamedHandler.reference("h.users . List").should eq({"h.users", "List"})
    Noir::GoNamedHandler.reference("func(c *gin.Context) {}").should be_nil
    Noir::GoNamedHandler.reference("wrap(listA)").should be_nil
  end

  it "claims a bare handler's body and attributes it to the routes naming it" do
    source = <<-GO
      package main

      func main() {
      \tr.GET("/a", listA)
      \tr.GET("/b", listB)
      }

      func listA(c *gin.Context) {
      \t_ = c.Query("qa")
      }
      GO
    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    named = Noir::GoNamedHandler.new(source, "main.go", routes)
    source.lines.each_with_index { |line, i| named.claim?(i, line) }
    a = Endpoint.new("/a", "GET")
    named.bind("listA", a)
    named.bind("listB", Endpoint.new("/b", "GET"))

    seen = [] of Tuple(String, String)
    named.each_attribution { |line, ep| seen << {ep.url, line.strip} }
    seen.should contain({"/a", %(_ = c.Query("qa"))})
    seen.all? { |url, _| url == "/a" }.should be_true
  end

  it "leaves a method name shared by two receivers to the legacy path" do
    claimed_rows(<<-GO).should be_empty
      package main

      func main() {
      \tr.GET("/users", u.List)
      \tr.GET("/posts", p.List)
      }

      func (u *Users) List(c *gin.Context) { _ = c.Query("user_q") }

      func (p *Posts) List(c *gin.Context) { _ = c.Query("post_q") }
      GO
  end

  it "leaves a package-qualified handler to the legacy path" do
    claimed_rows(<<-GO).should be_empty
      package main

      import "example.com/app/handlers"

      func main() {
      \tr.GET("/show", handlers.Show)
      }

      func (l *local) Show(c *gin.Context) { _ = c.Query("local_q") }
      GO
  end

  it "claims a single receiver's method named through a selector" do
    claimed_rows(<<-GO).should eq([6])
      package main

      func main() {
      \tr.GET("/users", h.List)
      }

      func (h *Users) List(c *gin.Context) { _ = c.Query("user_q") }
      GO
  end

  it "never claims a function that registers routes itself" do
    claimed_rows(<<-GO).should be_empty
      package main

      func main() {
      \tr.GET("/setup", setup)
      }

      func setup(c *gin.Context) {
      \tr.GET("/inner", inner)
      }
      GO
  end
end
