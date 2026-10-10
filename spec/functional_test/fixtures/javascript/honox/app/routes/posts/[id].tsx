import { createRoute } from "honox/factory";

export default createRoute((c) => c.render(<p>{c.req.param("id")}</p>));

export const DELETE = createRoute((c) => {
  const key = c.req.header("X-Api-Key");
  return c.json({ deleted: Boolean(key) });
});
