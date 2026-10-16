import { withMiddlewares } from "../../lib/with-middlewares";

// The wrapper answers 405 for any verb that is not a key of the map.
export default withMiddlewares({
  GET: async (req, res) => {
    res.status(200).json({ comments: [] });
  },
  POST: async (req, res) => {
    res.status(201).json({ ok: true });
  },
});
