# The main map mounts each app's sub-map under a prefix. A `path ""`
# mount must NOT surface as a `/", Blog::ROUTES, name:` junk endpoint, the
# mount point itself is not a leaf route, and the sub-map's routes inherit
# the mount prefix instead of being emitted bare.
Marten.routes.draw do
  path "", Blog::ROUTES, name: "blog"
  path "/auth", Auth::ROUTES, name: "auth"
  path "/health", HealthHandler, name: "health"

  if Marten.env.development?
    path "/__debug", DebugHandler, name: "debug"
  end
end
