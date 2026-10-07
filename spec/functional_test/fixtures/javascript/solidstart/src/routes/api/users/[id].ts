import type { APIEvent } from "@solidjs/start/server";

export const GET = async ({ params }: APIEvent) => Response.json({ id: params.id });

export const DELETE = async ({ params }: APIEvent) => new Response(null, { status: 204 });
