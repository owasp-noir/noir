import type { RequestHandler } from "@builder.io/qwik-city";

export const onGet: RequestHandler = async ({ json }) => {
  json(200, await listUsers());
};

export const onPost: RequestHandler = async ({ parseBody, json }) => {
  const body = await parseBody();
  json(201, await createUser(body));
};
