import { query } from "convex/server";
import { v } from "convex/values";

// Not an HTTP route: no httpRouter here, so this look-alike object is ignored.
const options = { path: "/notARoute", method: "GET", handler: () => null };

export const list = query({
  args: { channel: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db.query("messages").collect();
  },
});
