import type { RequestHandler } from '@sveltejs/kit';

export const GET: RequestHandler = async ({ request }) => {
    return new Response(JSON.stringify([]), {
        headers: { 'Content-Type': 'application/json' },
    });
};

export const POST: RequestHandler = async ({ request }) => {
    const body = await request.json();
    return new Response(JSON.stringify(body), { status: 201 });
};
