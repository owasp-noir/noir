import { db } from "~/server/db";

export default defineEventHandler(async (event) => {
  const query = getQuery(event);
  const page = Number(query.page ?? 1);
  const users = await db.query.users.findMany({ limit: 10, offset: page * 10 });
  return { users };
});
