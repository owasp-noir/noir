import type { Config, Context } from "@netlify/functions";

export default async (req: Request, context: Context) => {
  const name = new URL(req.url).searchParams.get(/* who */ "name") ?? "World";
  return new Response(`Hello ${name}`);
};

export const config: Config = {
  path: "/api/hello",
  method: "GET",
};
