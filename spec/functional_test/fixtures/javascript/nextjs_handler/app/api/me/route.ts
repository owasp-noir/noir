import { withAuth } from "../../../lib/responder";

async function getHandler(req: Request) {
  const user = await loadUser(req);
  return Response.json(user);
}

export const GET = withAuth(getHandler);

export async function POST(req: Request) {
  return Response.json({ ok: true });
}
