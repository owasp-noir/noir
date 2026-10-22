"use strict";

module.exports = {
  name: "orders",
  version: 2,
  actions: {
    // A path-only `rest` takes any verb.
    find: { rest: "/find", handler() {} },
  },
};
