import { waitUntil } from "@vercel/functions";

export async function GET(request: Request) {
  waitUntil(Promise.resolve());
  return Response.json([]);
}
