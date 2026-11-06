require "spec"
require "../../../src/miniparsers/go_route_extractor_ts"

# chi serves a sub-router built in a function and mounted by name under the
# mount prefix, whether its routes are registered before or after the Mount.
describe "Noir::TreeSitterGoRouteExtractor chi local mounts" do
  it "prefixes a named sub-router's routes with its mount path" do
    source = <<-GO
      package routes
      func (h *BadgeHandler) RegisterRoutes(router chi.Router) {
          r := chi.NewRouter()
          r.Use(auth)
          r.Get("/{user}/*", h.Get)
          router.Mount("/badge", r)
      }
      func main() {
          router := chi.NewRouter()
          api := chi.NewRouter()
          router.Mount("/api", api)
          sub := chi.NewRouter()
          api.Mount("/sub/", sub)
          sub.Get("/x", hx)
          router.Get("/root", hr)
      }
      func other(r chi.Router) {
          r.Get("/plain", hp)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_chi_routes(source)
    routes.map(&.path).sort!.should eq(["/api/sub/x", "/badge/{user}/*", "/plain", "/root"].sort)
  end

  it "keeps a name declared more than once, mounted twice, or mounted on a closure's router as read" do
    source = <<-GO
      package routes
      func main() {
          r := chi.NewRouter()
          r.Get("/home", h)
          register := func(parent chi.Router) {
              r := chi.NewRouter()
              r.Get("/x", h)
              parent.Mount("/v", r)
          }
          register(r)
          r.Route("/api", func(api chi.Router) {
              sub := chi.NewRouter()
              sub.Get("/s", h)
              api.Mount("/sub", sub)
          })
      }
      func (h *H) Settings(router chi.Router) {
          router.Group(func(r chi.Router) {
              r.Get("/public", h.x)
          })
          r := chi.NewRouter()
          r.Get("/", h.x)
          router.Mount("/settings", r)
      }
      func twice(router chi.Router) {
          m := chi.NewRouter()
          m.Get("/m", h)
          router.Mount("/one", m)
          router.Mount("/two", m)
      }
      func reassigned(router chi.Router) {
          s := chi.NewRouter()
          s.Get("/s1", h)
          router.Mount("/a", s)
          s = chi.NewRouter()
          s.Get("/s2", h)
          router.Mount("/b", s)
      }
      func params(router chi.Router) {
          u := chi.NewRouter()
          u.Get("/profile", h)
          router.Mount("/users/{userID}", u)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_chi_routes(source)
    routes.map(&.path).sort!.should eq([
      # `/x` is walked through the `register(r)` helper call, as on main
      "/home", "/x", "/api/s",
      "/public", "/",
      "/m", "/s1", "/s2",
      "/users/{userID}/profile",
    ].sort)
  end
end
