import type { VercelRequest, VercelResponse } from "@vercel/node";
import { loadUser, saveUser } from "../_lib/db";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method === "GET") {
    return res.json(await loadUser(req.query.id));
  }
  if (req.method === "PATCH") {
    const { displayName } = req.body;
    const token = req.headers["x-csrf-token"];
    return res.json(await saveUser(req.query.id, displayName, token));
  }
  res.status(405).end();
}
