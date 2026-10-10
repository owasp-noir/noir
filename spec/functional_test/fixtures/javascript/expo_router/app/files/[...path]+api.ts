export async function GET(request: Request, { path }: Record<string, string>) {
  return new Response(path);
}
