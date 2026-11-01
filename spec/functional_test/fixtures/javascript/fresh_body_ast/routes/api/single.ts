import { runAll } from "../../lib/thing.ts";

export const handler = async (req: Request): Promise<{ done: true }> => {
  return Response.json(await runAll(req));
};
