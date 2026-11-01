import type { VercelRequest, VercelResponse } from "@vercel/node";
import { save } from "../lib/save";

type Handler = (req: VercelRequest, res: VercelResponse) => Promise<unknown>;

export const PUT = (async (req: VercelRequest, res: VercelResponse): Promise<{ saved: boolean }> => {
  const { name } = req.body;
  return res.json(await save(name));
}) satisfies Handler;

export const DELETE: Handler = async (req, res) => res.json(await save(req.query.id));
