import type { RequestHandler } from "@builder.io/qwik-city";

export const onRequest: RequestHandler = async ({ next }) => {
  await next();
};
