import type { APIRoute } from "astro";

export const GET: APIRoute = () => new Response("get");

export const ALL: APIRoute = ({ request }) => new Response(`This was a ${request.method}!`);
