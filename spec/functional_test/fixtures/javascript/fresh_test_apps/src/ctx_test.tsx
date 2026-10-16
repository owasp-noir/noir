import { App } from "fresh";

Deno.test("old", () => {
  const app = new App();
  app.get("/old", () => new Response("old"));
});
