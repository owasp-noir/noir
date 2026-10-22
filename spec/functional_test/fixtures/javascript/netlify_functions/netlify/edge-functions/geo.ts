import type { Config, Context } from "@netlify/edge-functions";

export default async (request: Request, context: Context) => {
  const lang = request.headers.get("accept-language");
  return Response.json({ country: context.geo.country, lang });
};

export const config: Config = { path: "/geo" };
