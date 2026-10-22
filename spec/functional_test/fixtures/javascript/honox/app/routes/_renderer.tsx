import { jsxRenderer } from "hono/jsx-renderer";

export default jsxRenderer(({ children }) => <html><body>{children}</body></html>);
