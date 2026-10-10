require "../../func_spec.cr"

# koa-router children imported by name
# (`const { usersRouter } = require('./routes/users')`,
# `const { router: postsRouter } = require('./routes/posts')`) and mounted
# with `router.use('/users', usersRouter.routes())`. Only default imports
# were resolved, so these routes were reported at their bare paths.

FunctionalTester.new("fixtures/javascript/koa_named_import_mount/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/users/list", "GET"),
  Endpoint.new("/posts/recent", "GET"),
]).perform_tests
