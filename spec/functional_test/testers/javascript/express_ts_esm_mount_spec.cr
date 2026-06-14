require "../../func_spec.cr"

# TypeScript ESM (`moduleResolution: NodeNext`) imports a sibling `.ts`
# source through a `.js` specifier (`import usersRouter from
# './controllers/users.js'` where the file on disk is `users.ts`).
# The cross-file router-mount resolver must rewrite the `.js` extension
# to its `.ts` counterpart, otherwise the mount prefix never attaches
# and every sub-route loses it (`/me` instead of `/users/me`).
expected_endpoints = [
  Endpoint.new("/users/me", "GET"),
  Endpoint.new("/users/:id", "GET"),
  Endpoint.new("/posts/", "GET"),
  Endpoint.new("/posts/", "POST"),
]

FunctionalTester.new("fixtures/javascript/express_ts_esm_mount/", {
  :techs => 1,
}, expected_endpoints).perform_tests
