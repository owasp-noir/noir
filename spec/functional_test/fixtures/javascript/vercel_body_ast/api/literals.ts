import type { VercelRequest, VercelResponse } from "@vercel/node";
import { render } from "../lib/render";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // braces in a template literal expression and a regex literal
  const label = `limit=${ { a: 1 }.a } ${ `${ "}" }` }`;
  const closing = /}{/.test(label) ? 1 : 0;
  const token = req.headers["x-literal-token"];
  const nested = (function inner() {
    return { deep: { deeper: [1, 2, { three: 3 }] } };
  })();
  return res.json(await render(label, closing, token, nested, req.query.after));
}
