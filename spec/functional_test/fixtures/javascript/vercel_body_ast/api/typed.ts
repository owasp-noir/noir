import type { VercelRequest, VercelResponse } from "@vercel/node";
import { loadTyped } from "../lib/typed";

// The return type is an object literal type: the first `{` after the
// parameter list is the type's, not the body's.
export async function GET(req: VercelRequest, res: VercelResponse): Promise<{ ok: true; items: string[] }> {
  const page = req.query.page;
  return res.json(await loadTyped(page));
}

export async function POST(req: VercelRequest, res: VercelResponse): Promise<void> {
  const { title } = req.body;
  res.status(201).json(await loadTyped(title));
}
