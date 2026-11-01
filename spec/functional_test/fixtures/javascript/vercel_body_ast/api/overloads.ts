import type { VercelRequest, VercelResponse } from "@vercel/node";
import { lookup } from "../lib/lookup";

export function GET(req: VercelRequest): { a: 1 };
export function GET(req: VercelRequest, res: VercelResponse): { b: 2 };
export function GET(req: VercelRequest, res?: VercelResponse): { a: 1 } | { b: 2 } {
  const filter = req.query.filter;
  return res ? res.json(lookup(filter)) : lookup(filter);
}
