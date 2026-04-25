import { Handlers, PageProps } from "$fresh/server.ts";

export const handler: Handlers = {
    GET: (req, ctx) => ctx.render({ slug: ctx.params.slug }),
};

export default function Catchall({ data }: PageProps) {
    return <h1>Catch-all</h1>;
}
