// A `functions/` directory that is not at the project root is not routed.
export const onRequest = () => new Response("not a route");
