import type { APIRoute } from "astro";

export const GET: APIRoute = async ({ cookies }) => new Response(cookies.get("sid")?.value ?? "");

// Disabled until CSRF protection lands:
// export const DELETE: APIRoute = async ({ cookies }) => { cookies.delete("sid"); return new Response(null); };
