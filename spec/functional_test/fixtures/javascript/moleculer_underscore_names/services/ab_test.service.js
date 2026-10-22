const ApiGateway = require("moleculer-web");

module.exports = {
  name: "ab",
  mixins: [ApiGateway],
  settings: { routes: [{ path: "/ab", aliases: { "GET variant": "ab.variant" } }] },
  actions: {
    variant: { handler() { return "a"; } },
  },
};
