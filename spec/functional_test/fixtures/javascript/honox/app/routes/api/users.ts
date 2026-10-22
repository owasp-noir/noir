import { createRoute } from "honox/factory";

export const POST = createRoute(async (c) => {
  const { name, email } = await c.req.parseBody();
  return c.json({ name, email }, 201);
});

export default createRoute((c) => {
  const page = c.req.query(/* 1-based */ "page");
  return c.json({ page, users: [] });
});
