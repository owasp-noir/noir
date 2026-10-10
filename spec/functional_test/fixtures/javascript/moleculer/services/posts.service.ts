import type { ServiceSchema } from "moleculer";

// Reached only through the gateway's `REST posts` alias: no `rest:` fields.
const PostsService: ServiceSchema = {
  name: "posts",
  actions: {
    list: { params: { page: "number" }, handler: async () => [] },
    get: { params: { id: "string" }, handler: async () => null },
    create: { params: { title: "string", body: "string" }, handler: async () => null },
    update: { handler: async () => null },
    patch: { handler: async () => null },
    remove: { handler: async () => null },
  },
};

export default PostsService;
