import type { NetlifyFunction } from "@netlify/functions";

export default {
  async fetch(req: Request) {
    const token = req.headers.get("x-token");
    return new Response(token ? "ok" : "denied");
  },
  config: {
    path: "/api/fetchable",
  },
} satisfies NetlifyFunction;
