import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";

// A load-test endpoint that the product exposes, not a test file.
const http = httpRouter();

http.route({
  path: "/loadtest",
  method: "POST",
  handler: httpAction(async () => new Response(null, { status: 200 })),
});

export default http;
