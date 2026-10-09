// Runs before every route; not a route itself.
export const onRequest: PagesFunction = async ({ request, next }) => {
  if (!request.headers.get("x-api-key")) {
    return new Response("unauthorized", { status: 401 });
  }
  return next();
};
