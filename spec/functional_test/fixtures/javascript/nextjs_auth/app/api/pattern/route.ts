import { auth } from "@/lib/auth";
import { withPattern, handler } from "@/lib/x";

export const GET = withPattern(handler, /^\(/);

export async function POST(request: Request) {
  const session = await auth();
  if (!session) {
    return Response.json({ error: "no" }, { status: 401 });
  }
  return Response.json([]);
}
