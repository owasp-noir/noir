import type { APIRoute } from 'astro';

export const GET: APIRoute = async ({ request }) => {
    return new Response(JSON.stringify([]), {
        headers: { 'Content-Type': 'application/json' },
    });
};

export const POST: APIRoute = async ({ request }) => {
    const data = await request.json();
    return new Response(JSON.stringify(data), { status: 201 });
};
