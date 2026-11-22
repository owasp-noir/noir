const express = require('express');
if (process.argv[2] === '--version') {
  console.log(require('express/package.json').version);
  process.exit(0);
}

// Express 5 compiles mount strings into opaque matcher closures. Keep the
// argument on the corresponding live layer; the stack determines reachability.
const mounts = new WeakMap();
const use = express.Router.prototype.use;
express.Router.prototype.use = function (path, ...handlers) {
  const start = this.stack.length;
  const result = use.call(this, path, ...handlers);
  for (const layer of this.stack.slice(start)) {
    if (layer.handle.stack) {
      if (typeof path !== 'string') throw new Error('Expected a literal router mount');
      mounts.set(layer, path);
    }
  }
  return result;
};

let app;
try {
  app = require('./src/app');
} finally {
  express.Router.prototype.use = use;
}

const rows = [];
function walk(stack, prefix) {
  for (const layer of stack) {
    if (layer.route) {
      const path = prefix + String(layer.route.path);
      for (const key of Object.keys(layer.route.methods)) {
        rows.push({ method: key === '_all' ? 'ALL' : key.toUpperCase(), path });
      }
    } else if (mounts.has(layer)) {
      walk(layer.handle.stack, prefix + mounts.get(layer));
    }
  }
}
walk(app.router.stack, '');
rows.sort((a, b) => compare(a.path, b.path) || compare(a.method, b.method));
function compare(a, b) { return a < b ? -1 : a > b ? 1 : 0; }
console.log(JSON.stringify(rows, null, 2));
