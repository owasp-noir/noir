require "../../func_spec.cr"

# Routers mounted through a re-export barrel (`routes/index.js`):
#
#   export { default as users } from './users.js'      app.use('/users', routes.users)
#   import tagsRouter from './tags.js'; export { tagsRouter as tags }
#   module.exports = { accounts: require('./accounts'), admin }
#   export default { orders, carts }                    app.use('/orders', routes.orders)
#
# The mount prefix used to be keyed on the barrel, which defines no routes,
# so every router behind it was reported at its bare path.

FunctionalTester.new("fixtures/javascript/express_barrel_mount/", {
  :techs     => 1,
  :endpoints => 7,
}, [
  Endpoint.new("/users/list", "GET"),
  Endpoint.new("/posts/recent", "GET"),
  Endpoint.new("/tags/popular", "GET"),
  Endpoint.new("/api/accounts", "GET"),
  Endpoint.new("/admin/stats", "GET"),
  Endpoint.new("/orders/pending", "GET"),
  Endpoint.new("/carts/current", "GET"),
]).perform_tests
