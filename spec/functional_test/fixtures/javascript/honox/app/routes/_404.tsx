import type { NotFoundHandler } from "hono";

const handler: NotFoundHandler = (c) => c.render(<h1>Not found</h1>);
export default handler;
