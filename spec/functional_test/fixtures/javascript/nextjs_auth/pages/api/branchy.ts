import type { NextApiRequest, NextApiResponse } from "next";
import { getSession } from "next-auth/react";

async function requireSession(req: NextApiRequest, res: NextApiResponse) {
  const session = await getSession({ req });
  if (!session) {
    return res.status(401).json({ message: "Not authenticated" });
  }
}

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method === "GET") {
    return res.json({ public: true });
  }
  await requireSession(req, res);
  return res.json({ ok: true });
}
