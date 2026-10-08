import homepage from "./index.html";

const apiRoutes = {
  "/api/version": () => Response.json({ version: "1.0.0" }),
};

Bun.serve({
  port: 3000,
  routes: {
    "/": homepage,
    "/api/status": new Response("OK"),
    "/api/users": {
      GET: (req) => {
        const url = new URL(req.url);
        const page = url.searchParams.get("page");
        return Response.json({ page });
      },
      async POST(req) {
        const { name, email } = await req.json();
        return Response.json({ name, email }, { status: 201 });
      },
    },
    "/api/users/:id": async (req) => {
      const token = req.headers.get("authorization");
      const session = req.cookies.get("session");
      if (req.method === "DELETE") {
        return new Response(null, { status: 204 });
      }
      if (req.method === "PUT") {
        return Response.json({ id: req.params.id });
      }
      return new Response("Method not allowed", { status: 405 });
    },
    "/api/legacy": false,
  },
  async fetch(req) {
    const { pathname } = new URL(req.url);
    if (pathname === "/webhook" && req.method === "POST") {
      const form = await req.formData();
      const event = form.get("event");
      return new Response("ok");
    }
    return new Response("Not Found", { status: 404 });
  },
});

Bun.serve({ port: 3001, routes: apiRoutes, fetch: () => new Response("x") });

const options = {
  routes: {
    "/api/items": async (req: Request): Promise<Response> => {
      switch (req.method) {
        case "POST":
          return new Response("created");
        case "DELETE":
          return new Response(null, { status: 204 });
      }
      return new Response(null, { status: 405 });
    },
    "/api/upload": async (req) => {
      if (req.method !== "POST") return new Response(null, { status: 405 });
      const data = (await req.json()) as { title: string };
      return Response.json({ title: data?.title });
    },
  },
  static: {
    "/legacy": new Response("old"),
  },
};

Bun.serve(options);
