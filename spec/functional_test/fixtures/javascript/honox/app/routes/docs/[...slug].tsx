import { createRoute } from "honox/factory";

export default createRoute((c) => c.render(<article>{c.req.param("slug")}</article>));
