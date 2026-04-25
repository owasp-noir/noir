import { Handlers } from "$fresh/server.ts";

export const handler: Handlers = {
    GET(req) {
        return new Response("[]");
    },
    async POST(req) {
        const body = await req.json();
        return new Response(JSON.stringify(body), { status: 201 });
    },
};
