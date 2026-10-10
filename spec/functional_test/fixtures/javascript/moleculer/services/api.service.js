"use strict";

const ApiGateway = require("moleculer-web");

module.exports = {
  name: "api",
  mixins: [ApiGateway],
  settings: {
    port: 3000,
    routes: [
      {
        path: "/api",
        aliases: {
          "GET users": "users.list",
          "POST users": "users.create",
          "GET users/:id": "users.get",
          "REST posts": "posts",
          // No method: any verb.
          "health": "api.health",
        },
      },
      {
        path: "/auto",
        autoAliases: true,
      },
    ],
  },
  actions: {
    health() {
      return "ok";
    },
  },
};
