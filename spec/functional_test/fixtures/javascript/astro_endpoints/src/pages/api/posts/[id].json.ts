import type { APIRoute } from "astro";
export const GET: APIRoute = ({ params }) => new Response(JSON.stringify({ id: params.id }));
