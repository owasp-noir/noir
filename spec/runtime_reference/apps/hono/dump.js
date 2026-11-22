import { readFileSync } from 'node:fs';
import app from './src/app.js';
import { mark } from './src/routes/index.js';

if (process.argv[2] === '--version') {
  const pkg = new URL('./node_modules/hono/package.json', import.meta.url);
  console.log(JSON.parse(readFileSync(pkg, 'utf8')).version);
  process.exit(0);
}

// app.routes includes one row per handler, including use('*', mark).
// A pass-through middleware does not serve a path of its own.
const routes = new Map();
for (const { handler, method, path } of app.routes) {
  if (handler !== mark) routes.set(JSON.stringify([method, path]), { method, path });
}
function compare(a, b) { return a < b ? -1 : a > b ? 1 : 0; }
const rows = [...routes.values()].sort((a, b) => compare(a.path, b.path) || compare(a.method, b.method));
console.log(JSON.stringify(rows, null, 2));
