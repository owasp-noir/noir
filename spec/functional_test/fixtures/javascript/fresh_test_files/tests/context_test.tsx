import { App } from "fresh";

Deno.test("ctx.redirect preserves the search string", async () => {
  const app = new App()
    .get("/phantom-old", (ctx) => ctx.redirect("/phantom-new"));

  await app.handler()(new Request("http://localhost/phantom-old"));
});
