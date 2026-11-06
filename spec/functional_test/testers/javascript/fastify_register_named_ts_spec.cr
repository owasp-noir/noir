require "../../func_spec.cr"

# Plugins registered by imported name, the way a large TypeScript Fastify
# backend nests them:
#
#   server.register(async (v1) => { v1.register(registerV1Routes) }, { prefix: "/api/v1" })
#   server.register(registerAdminRouter, { prefix: "/admin" })   // export const registerAdminRouter = async (server) => { server.route({...}) }
#   await registerAccessRouter(pkiRouter)                        // a plugin called on the instance
#   import { registerEeRoutes } from "@app/ee/routes"            // tsconfig `paths` alias
#
# `server.route({ method, url })` routes in such plugins lost every prefix;
# two plugins exported by one file keep their own.

FunctionalTester.new("fixtures/javascript/fastify_register_named_ts/", {
  :techs     => 1,
  :endpoints => 10,
}, [
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/v1/license/plan", "GET"),
  Endpoint.new("/api/v1/admin/config", "GET"),
  Endpoint.new("/api/v2/legacy/admin/config", "GET"),
  Endpoint.new("/api/v1/read/items", "GET"),
  Endpoint.new("/api/v2/legacy/read/items", "GET"),
  Endpoint.new("/api/v1/write/items", "POST"),
  Endpoint.new("/api/v2/legacy/write/items", "POST"),
  Endpoint.new("/api/v1/pki/access/users/:userId", "DELETE", [Param.new("userId", "", "path")]),
  Endpoint.new("/api/v2/legacy/pki/access/users/:userId", "DELETE", [Param.new("userId", "", "path")]),
]).perform_tests
