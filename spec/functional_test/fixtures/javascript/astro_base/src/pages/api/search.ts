import type { APIRoute } from "astro";
export const GET: APIRoute = ({ url }) => new Response(url.searchParams.get("q"));
