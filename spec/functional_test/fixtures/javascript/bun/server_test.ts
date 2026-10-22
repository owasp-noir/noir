import { test } from "bun:test";

test("mock upstream", () => {
  Bun.serve({ routes: { "/mock-upstream": new Response("ok") } });
});
