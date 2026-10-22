"use strict";

module.exports = {
  name: "users",
  actions: {
    list: {
      rest: "GET /",
      params: { limit: { type: "number", optional: true } },
      handler(ctx) {
        return [];
      },
    },
    create: {
      rest: { method: "POST", path: "/" },
      params: { name: "string", email: "email", $$strict: true },
      handler(ctx) {
        return ctx.params;
      },
    },
    get: {
      rest: "GET /:id",
      params: { id: "string" },
      handler(ctx) {
        return { id: ctx.params.id };
      },
    },
  },
};
