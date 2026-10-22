export async function onRequest({ request, params }) {
  if (request.method === "PUT") {
    const session = request.headers.get("cookie");
    return new Response(`stored ${params.path}`);
  }
  if (request.method === "GET") {
    return new Response(params.path.join("/"));
  }
  return new Response(null, { status: 405 });
}
