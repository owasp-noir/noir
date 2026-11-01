import { Handlers } from "$fresh/server.ts";
import { loadThing, saveThing } from "../../lib/thing.ts";

export const handler: Handlers<{ items: string[] }> = {
  async GET(_req, ctx): Promise<Response> {
    const thing = await loadThing(ctx.params.id);
    return new Response(`${ { a: 1 }.a }${thing}`);
  },
  POST: async (req, _ctx) => {
    const body = await req.json();
    return new Response(await saveThing(body));
  },
};
