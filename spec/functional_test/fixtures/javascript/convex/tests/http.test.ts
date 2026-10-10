import { httpRouter } from "convex/server";

const http = httpRouter();
http.route({ path: "/only-in-test", method: "GET", handler: async () => new Response("") });
export default http;
