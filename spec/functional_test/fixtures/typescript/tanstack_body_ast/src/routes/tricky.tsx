import { createFileRoute, createRoute } from "@tanstack/react-router";
import { load, Tricky } from "../lib/tricky";

export const Route = createFileRoute("/tricky")({
  loader: async () => { const s = ")}("; return load(s, /\)\}/); },
  component: Tricky,
});

const code = createRoute({
  getParentRoute: () => rootRoute,
  path: "code",
  loader: async () => { const t = `)(${ { a: 1 }.a }`; return load(t); },
});
