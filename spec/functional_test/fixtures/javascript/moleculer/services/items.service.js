"use strict";

module.exports = {
  name: "items",
  // Several base paths: every `rest` route is served under each.
  settings: { rest: ["/items", "/things"] },
  actions: {
    // `s` is a query param even though `:sku` starts with `:s`.
    get: { rest: "GET /:sku", params: { sku: "string", s: "string" }, handler() {} },
    // moleculer-web reads only strings and objects; `true` adds no route.
    flag: { rest: true, handler() {} },
    // Non-published actions are skipped by autoAliases.
    secret: { rest: "GET /secret", visibility: "private", handler() {} },
  },
};
