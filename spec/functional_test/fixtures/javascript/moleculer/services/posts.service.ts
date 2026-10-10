import type { ServiceSchema } from "moleculer";

// Reached only through the gateway's `REST posts` alias: no `rest:` fields.
const PostsService: ServiceSchema = {
  name: "posts",
  actions: {
    list: { params: { page: "number" }, handler: async (ctx) => { if (ctx.meta.kind === "a:b") { return []; } } },
    get: { params: { id: "string" }, handler: async () => null },
    create: { params: { title: "string", body: "string" }, handler: async () => null },
    update: { handler(this: PostsThis, ctx: Context<UpdateParams>): Promise<null> { return null; } },
    patch: { handler: async () => null },
    remove: { handler: async () => null },
  },
};

export default PostsService;
