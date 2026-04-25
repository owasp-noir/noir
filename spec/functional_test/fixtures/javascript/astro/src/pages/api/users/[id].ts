import type { APIRoute } from 'astro';

export async function GET({ params }) {
    return new Response(JSON.stringify({ id: params.id }));
}

export async function PUT({ params, request }) {
    const body = await request.json();
    return new Response(JSON.stringify(body));
}

export async function DELETE({ params }) {
    return new Response(null, { status: 204 });
}
