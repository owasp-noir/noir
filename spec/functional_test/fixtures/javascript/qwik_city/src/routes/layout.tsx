import { component$, Slot } from "@builder.io/qwik";
import type { RequestHandler } from "@builder.io/qwik-city";

export const onGet: RequestHandler = async ({ cacheControl }) => {
  cacheControl({ maxAge: 5 });
};

export default component$(() => <Slot />);
