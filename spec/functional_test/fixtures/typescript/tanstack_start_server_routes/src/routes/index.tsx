import { createFileRoute } from "@tanstack/react-router";
import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";

export const saveNote = createServerFn({ method: "POST" })
  .inputValidator(z.object({ title: z.string() }))
  .handler(async ({ data }) => data.title);

export const Route = createFileRoute("/")({
  component: Home,
});

function Home() { return <div />; }
