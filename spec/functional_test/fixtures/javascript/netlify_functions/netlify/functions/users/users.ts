import type { Config, Context } from "@netlify/functions";
import { findUser } from "./helpers";

export default async (request: Request, context: Context) => {
  const auth = request.headers.get("authorization");
  return Response.json(await findUser(context.params.id, auth));
};

export const config: Config = {
  path: ["/api/users/:id", "/api/members/:id"],
  method: ["GET", "DELETE"],
};
