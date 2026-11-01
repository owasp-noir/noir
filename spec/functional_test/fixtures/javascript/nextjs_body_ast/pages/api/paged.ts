import type { NextApiRequest, NextApiResponse } from "next";
import { loadTyped } from "../../lib/typed";

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse<{ ok: true }>
): Promise<{ done: boolean }> {
  const page = req.query.page;
  res.status(200).json(await loadTyped(page));
  return { done: true };
}
