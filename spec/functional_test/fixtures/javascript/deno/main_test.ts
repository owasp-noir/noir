Deno.test("fetches a mock user", async () => {
  const server = Deno.serve({ port: 0 }, (req) => {
    const url = new URL(req.url);
    if (url.pathname === "/mock-user") return new Response("{}");
    return new Response("", { status: 404 });
  });
  await server.shutdown();
});
