import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/users/$id")({
  server: {
    handlers: ({ createHandlers }) =>
      createHandlers({
        DELETE: {
          middleware: [],
          handler: async ({ params }) => new Response(null, { status: 204 }),
        },
      }),
  },
});
