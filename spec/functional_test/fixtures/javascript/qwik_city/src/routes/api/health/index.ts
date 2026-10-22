import type { RequestHandler } from "@builder.io/qwik-city";

export const onRequest: RequestHandler = async ({ text }) => {
  text(200, "ok");
};
