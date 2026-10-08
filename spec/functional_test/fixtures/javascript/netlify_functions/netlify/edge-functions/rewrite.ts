// Path declared in netlify.toml ([[edge_functions]]), not inline.
export default async (request: Request) => {
  return new URL("/fallback", request.url);
};
