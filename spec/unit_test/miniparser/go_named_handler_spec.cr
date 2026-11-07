require "../../spec_helper"
require "../../../src/miniparsers/go_named_handler"

# Runs the full claim/bind/attribute cycle over `source` and returns the
# claimed lines (stripped) credited to each route URL.
private def attributions(source : String) : Hash(String, Array(String))
  routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
  named = Noir::GoNamedHandler.new(source, "main.go", routes)
  source.lines.each_with_index { |line, i| named.claim?(i, line) }
  routes.each { |route| named.bind(route, Endpoint.new(route.path, route.verb)) }
  seen = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }
  named.each_attribution { |line, ep| seen[ep.url] << line.strip }
  seen
end

private def credited?(source : String, url : String, text : String) : Bool
  attributions(source)[url].any?(&.includes?(text))
end

describe Noir::GoNamedHandler do
  it "parses plain handler references only" do
    Noir::GoNamedHandler.reference("listA").should eq({"", "listA"})
    Noir::GoNamedHandler.reference("h.users . List").should eq({"h.users", "List"})
    Noir::GoNamedHandler.reference("RateLimit()").should eq({"", "RateLimit"})
    Noir::GoNamedHandler.reference("func(c *gin.Context) {}").should be_nil
    Noir::GoNamedHandler.reference("wrap(listA)").should be_nil
  end

  it "attributes a bare handler's body to the route naming it" do
    seen = attributions(<<-GO)
      package main

      func main() {
      \tr.GET("/a", listA)
      \tr.GET("/b", listB)
      }

      func listA(c *gin.Context) {
      \t_ = c.Query("qa")
      }
      GO
    seen["/a"].should contain(%(_ = c.Query("qa")))
    seen.keys.should eq(["/a"])
  end

  it "binds every handler of a middleware chain, including an append spread" do
    source = <<-GO
      package main

      func main() {
      \tr.GET("/x", RateLimit(), listX)
      \th.GET("/y", append(mws(), listY)...)
      }

      func listX(c *gin.Context) { _ = c.Query("qx") }

      func listY(ctx context.Context, c *app.RequestContext) { _ = c.Query("qy") }
      GO
    credited?(source, "/x", "qx").should be_true
    credited?(source, "/y", "qy").should be_true
  end

  it "resolves same-named methods by the qualifier's declared receiver type" do
    source = <<-GO
      package main

      func main() {
      \tusers := &Users{}
      \tposts := new(Posts)
      \tr.GET("/users", users.List)
      \tr.GET("/posts", posts.List)
      }

      func (u *Users) List(c *gin.Context) { _ = c.Query("user_q") }

      func (p *Posts) List(c *gin.Context) { _ = c.Query("post_q") }
      GO
    seen = attributions(source)
    seen["/users"].join.should contain("user_q")
    seen["/users"].join.should_not contain("post_q")
    seen["/posts"].join.should contain("post_q")
    seen["/posts"].join.should_not contain("user_q")
  end

  it "does not type the second name of a multi-assignment by the first value" do
    # `b` is not an `*X`: crediting `X.List` to `b.List` would be a phantom.
    attributions(<<-GO).should be_empty
      package main

      func main() {
      \ta, b := &X{}, newY()
      \tr.GET("/b", b.List)
      }

      func (x *X) List(c *gin.Context) { _ = c.Query("x_only") }
      GO
  end

  it "indexes declarations once per file (stays linear in selector routes)" do
    n = 4000
    source = String.build do |io|
      io << "package main\n\nfunc main() {\n\th := &H{}\n"
      n.times { |i| io << "\tr.GET(\"/r" << i << "\", h.M" << i << ")\n" }
      io << "}\n\n"
      n.times { |i| io << "func (h *H) M" << i << "(c *gin.Context) { _ = c.Query(\"q" << i << "\") }\n" }
    end
    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    routes.size.should eq(n)
    Noir::GoCalleeExtractor.collect_method_bodies(source, "perf.go")

    elapsed = Time.measure { Noir::GoNamedHandler.new(source, "perf.go", routes) }
    # Re-scanning the file per qualifier took ~4s here; linear is ~0.1s.
    elapsed.should be < 2.seconds
  end

  it "does not credit a local method when the qualifier's type is declared elsewhere" do
    attributions(<<-GO).should be_empty
      package main

      func (s *server) List(c *gin.Context) { _ = c.Query("server_only") }

      func main() {
      \tr.GET("/users", users.List)
      }
      GO
  end

  it "leaves a package-qualified handler to the legacy path" do
    attributions(<<-GO).should be_empty
      package main

      import "example.com/app/handlers"

      func main() {
      \tr.GET("/show", handlers.Show)
      }

      func (handlers *local) Show(c *gin.Context) { _ = c.Query("local_q") }
      GO
  end

  it "never claims a function that registers routes itself" do
    attributions(<<-GO).should be_empty
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

describe "Noir::GoNamedHandler wrapped handlers and callees" do
  it "binds a wrapper's functions and a handler's 1-hop callees, and credits no orphan" do
    seen = attributions(<<-GO)
      package main

      func main() {
      \tr.GET("/a", guard(func(c *gin.Context) { listA(c) }))
      \tr.GET("/b", listB)
      }

      func guard(next gin.HandlerFunc) gin.HandlerFunc {
      \treturn func(c *gin.Context) { _ = c.GetHeader("X-Guard") }
      }

      func listA(c *gin.Context) { _ = c.Query("qa") }

      func listB(c *gin.Context) { parseB(c) }

      func parseB(c *gin.Context) { _ = c.Query("qb") }

      func orphan(c *gin.Context) { _ = c.Query("qo") }
      GO
    seen["/a"].join.should contain("X-Guard")
    seen["/a"].join.should contain("qa")
    seen["/b"].join.should contain("qb")
    seen.values.flatten.join.should_not contain("qo")
  end
end

describe "Noir::GoNamedHandler middleware path params" do
  it "credits a middleware path read only to a route whose url has the slot" do
    seen = attributions(<<-GO)
      package main

      func Auth() fiber.Handler {
      \treturn func(c *fiber.Ctx) error {
      \t\t_ = c.Get("Authorization")
      \t\t_ = c.Query("redirect")
      \t\t_ = c.Params("userId")
      \t\treturn c.Next()
      \t}
      }

      func ginAuth(c *gin.Context) {
      \t_ = c.Param("id")
      \t_ = c.Query("q")
      }

      func chiAuth(w http.ResponseWriter, r *http.Request) {
      \t_ = chi.URLParam(r, "slug")
      \t_ = r.Header.Get("X-Token")
      }

      func muxAuth(w http.ResponseWriter, r *http.Request) {
      \t_ = mux.Vars(r)["name"]
      }

      func listUsers(c *fiber.Ctx) error { return c.SendString("ok") }
      func getUser(c *fiber.Ctx) error   { return c.SendString(c.Params("userId")) }
      func sendEmail(c *fiber.Ctx) error { return c.SendString("ok") }
      func listP(c *gin.Context)         {}
      func getP(c *gin.Context)          {}
      func listItems(w http.ResponseWriter, r *http.Request) {}
      func showItem(w http.ResponseWriter, r *http.Request)  {}
      func listMux(w http.ResponseWriter, r *http.Request)   {}
      func showMux(w http.ResponseWriter, r *http.Request)   {}

      // The handler itself reads `team`. No sibling route slots it, so the
      // read stays: the prefix may be the part noir could not resolve.
      func only(c *fiber.Ctx) error { return c.SendString(c.Params("team")) }

      func main() {
      \tr.GET("/v1/users/", Auth(), listUsers)
      \tr.GET("/v1/users/:userId", Auth(), getUser)
      \tr.POST("/v1/auth/send-verification-email", Auth(), sendEmail)
      \tr.GET("/p", ginAuth, listP)
      \tr.GET("/p/:id", ginAuth, getP)
      \tr.GET("/items", chiAuth, listItems)
      \tr.GET("/items/{slug}", chiAuth, showItem)
      \tr.GET("/mux", muxAuth, listMux)
      \tr.GET("/mux/{name}", muxAuth, showMux)
      \tr.GET("/list", only)
      }
      GO

    users = seen["/v1/users/"].join
    users.should contain(%(c.Get("Authorization")))
    users.should contain(%(c.Query("redirect")))
    users.should_not contain(%(Params("userId")))

    email = seen["/v1/auth/send-verification-email"].join
    email.should contain(%(c.Get("Authorization")))
    email.should_not contain(%(Params("userId")))

    slotted = seen["/v1/users/:userId"].join
    slotted.should contain(%(Params("userId")))
    slotted.should contain(%(c.Get("Authorization")))

    seen["/p"].join.should_not contain(%(Param("id")))
    seen["/p"].join.should contain(%(c.Query("q")))
    seen["/p/:id"].join.should contain(%(Param("id")))

    seen["/items"].join.should_not contain(%(URLParam(r, "slug")))
    seen["/items"].join.should contain(%(Header.Get("X-Token")))
    seen["/items/{slug}"].join.should contain(%(URLParam(r, "slug")))

    seen["/mux"].join.should_not contain(%(Vars(r)["name"]))
    seen["/mux/{name}"].join.should contain(%(Vars(r)["name"]))

    seen["/list"].join.should contain(%(Params("team")))
  end
end

describe "Noir::GoNamedHandler#handler_for" do
  it "reports the last argument only: a named handler or the closure, never a middleware before a closure" do
    source = <<-GO
      package main

      func main() {
      	r.GET("/home", CookieTool(), func(c *gin.Context) {})
      	r.GET("/stream", HeadersMiddleware(), stream.serveHTTP())
      	r.POST("/items", Auth(), createItem)
      }

      func CookieTool() gin.HandlerFunc { return nil }
      func HeadersMiddleware() gin.HandlerFunc { return nil }
      func Auth() gin.HandlerFunc { return nil }
      func createItem(c *gin.Context) {}
      func (stream *Event) serveHTTP() gin.HandlerFunc { return nil }
      GO
    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    named = Noir::GoNamedHandler.new(source, "main.go", routes)
    by_path = routes.to_h { |r| {r.path, named.handler_for(r)} }
    by_path["/home"].should eq(Handler.new("closure", "main.go", 4))
    by_path["/items"].try(&.name).should eq("createItem")
    by_path["/items"].try(&.line).should eq(12)
    by_path["/stream"].try(&.name).should eq("stream.serveHTTP()")
  end
end
