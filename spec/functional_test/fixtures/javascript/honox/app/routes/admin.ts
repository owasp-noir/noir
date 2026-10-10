import { Hono } from "hono";

const app = new Hono();

app.get("/", (c) => c.json({ admin: true }));
app.post("/reindex/:index", (c) => c.json({ index: c.req.param("index") }));

export default app;
