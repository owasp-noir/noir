import { Handlers, PageProps } from "$fresh/server.ts";

export const handler: Handlers = {
    async GET(req, ctx) {
        return ctx.render({ id: ctx.params.id });
    },
    async PUT(req, ctx) {
        return new Response(null, { status: 200 });
    },
    async DELETE(req, ctx) {
        return new Response(null, { status: 204 });
    },
};

export default function User({ data }: PageProps) {
    return <h1>User</h1>;
}
