const ApiGateway = require("moleculer-web");

broker.createService({
  name: "api-test",
  mixins: [ApiGateway],
  settings: { routes: [{ path: "/test-only", aliases: { "GET secret": "x.y" } }] },
});
