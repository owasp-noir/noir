// Single-function handler — answers every method.
import { Handlers } from "$fresh/server.ts";

export const handler = (req) => new Response("ok");
