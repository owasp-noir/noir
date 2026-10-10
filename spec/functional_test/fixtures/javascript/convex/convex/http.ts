import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { api } from "./_generated/api";
import { stripeWebhook } from "./stripe";

const http = httpRouter();

http.route({
  path: "/postMessage",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const { author, body } = await request.json();
    await ctx.runMutation(api.messages.send, { author, body });
    return new Response(null, { status: 200 });
  }),
});

// Prefix routes match everything below the prefix.
http.route({
  pathPrefix: "/getAuthorMessages/",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    return new Response("ok");
  }),
});

http.route({ path: /* webhook */ "/stripe", method: "POST", handler: stripeWebhook });

export default http;
