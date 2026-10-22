"use strict";

// Shaped like a gateway, but nothing mixes in moleculer-web, so it is not routed.
module.exports = {
  name: "proxy-config",
  settings: {
    routes: [{ path: "/nope", aliases: { "GET leak": "proxy.leak" } }],
  },
};
