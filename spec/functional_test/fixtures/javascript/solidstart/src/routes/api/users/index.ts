import type { APIEvent } from "@solidjs/start/server";

export async function GET(event: APIEvent) {
  return Response.json(await listUsers());
}

export async function POST({ request }: APIEvent) {
  const body = await request.json();
  return Response.json(await createUser(body));
}
