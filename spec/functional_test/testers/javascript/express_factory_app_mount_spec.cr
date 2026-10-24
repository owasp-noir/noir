require "../../func_spec.cr"

# Apps built by factory modules and mounted through a project-local wrapper:
#
#   app.lazyUse = function lazyUse(mountPath, requireFn) { app.use(mountPath, …) }
#   backendApp.lazyUse(API_PATH, require('./api'))   // API_PATH imported
#   web/api/index.js: module.exports = require('./app')
#   apiApp.lazyUse('/admin/', require('./admin/app'))
#   adminApp.use(routes())
#
# The wrapper was not a mount, the imported constant was not a prefix, the
# prefix stuck to the `index.js` barrel, and the unplaced-mount pass put
# `/admin/` and `/api/member` at the root before their parents were placed.

FunctionalTester.new("fixtures/javascript/express_factory_app_mount/", {
  :techs     => 1,
  :endpoints => 4,
}, [
  Endpoint.new("/blog/api/admin/posts", "GET"),
  Endpoint.new("/blog/api/admin/posts/:id", "PUT"),
  Endpoint.new("/members/api/member/", "PUT"),
  Endpoint.new("/members/api/session", "POST"),
]).perform_tests
