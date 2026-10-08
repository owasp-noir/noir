import { findUser, deleteUser } from "../_lib/users";

interface Env {
  DB: D1Database;
}

export const onRequestGet: PagesFunction<Env> = async ({ request, params, env }) => {
  const token = request.headers.get("Authorization");
  const user = await findUser(env.DB, params.id as string, token);
  return Response.json(user);
};

export async function onRequestDelete(context) {
  const reason = new URL(context.request.url).searchParams.get("reason");
  await deleteUser(context.env.DB, context.params.id, reason);
  return new Response(null, { status: 204 });
}
