import { createFileRoute } from "@tanstack/react-router";
import { json } from "@tanstack/react-start";

export const Route = createFileRoute("/api/users")({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const q = new URL(request.url).searchParams.get("q");
        return json({ q });
      },
      POST: async ({ request }) => {
        const body = await request.json();
        return json({ name: body.name }, { status: 201 });
      },
    },
  },
});
