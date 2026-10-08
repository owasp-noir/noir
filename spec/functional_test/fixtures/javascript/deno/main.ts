const BOOK_ROUTE = new URLPattern({ pathname: "/books/:id" });
const AUTHOR_ROUTE = new URLPattern({ pathname: "/authors/:name" });

async function handler(req: Request): Promise<Response> {
  const match = BOOK_ROUTE.exec(req.url);
  if (match) {
    const id = match.pathname.groups.id;
    return new Response(`Book ${id}`);
  }

  if (req.method === "POST" && AUTHOR_ROUTE.test(req.url)) {
    return new Response("created", { status: 201 });
  }

  const url = new URL(req.url);
  if (url.pathname === "/search") {
    const q = url.searchParams.get("q");
    return new Response(q);
  }
  if (url.pathname === "/login" && req.method === "POST") {
    const body = await req.json();
    const user = body.username;
    const key = req.headers.get("x-api-key");
    return new Response(user);
  }

  return new Response("Not found", { status: 404 });
}

Deno.serve(handler);

Deno.serve({ port: 8001 }, async (request) => {
  const { pathname } = new URL(request.url);
  switch (pathname) {
    case "/health":
      return new Response("ok");
  }
  return new Response("nope", { status: 404 });
});

Deno.serve({
  port: 8002,
  handler: (req) => {
    const url = new URL(req.url);
    if (url.pathname === "/metrics") return new Response("");
    return new Response("", { status: 404 });
  },
});

const ITEM_ROUTE = new URLPattern({ pathname: "/items/:sku" });

Deno.serve({ port: 8003 }, (req) => {
  const m = ITEM_ROUTE.exec(req.url);
  if (!m) return new Response("", { status: 404 });
  return new Response(m.pathname.groups.sku);
});

const ORDER_ROUTE = new URLPattern({ pathname: "/orders/:id" });
const INVOICE_ROUTE = new URLPattern({ pathname: "/invoices/:id" });

Deno.serve({ port: 8004 }, async (req: Request): Promise<Response> => {
  if (req.method === "GET") {
    const match = ORDER_ROUTE.exec(req.url);
    if (match) return new Response("order");
  }
  if (req.method === "POST") {
    const match = INVOICE_ROUTE.exec(req.url);
    if (match) return new Response("invoice");
  }
  return new Response("", { status: 404 });
});

const CART_ROUTE = new URLPattern({ pathname: "/carts/:id" });

Deno.serve({ port: 8005 }, (req) => {
  const m = CART_ROUTE.exec(req.url);
  if (!m) return new Response("", { status: 404 });
  if (req.method === "DELETE") {
    return new Response(null, { status: 204 });
  }
  return new Response("", { status: 405 });
});
