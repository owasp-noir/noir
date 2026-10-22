import { apiHandler } from "../../lib/api-handler";
import { GET, removeTrace } from "../../lib/traces";

// Quoted key, shorthand key and method shorthand.
export default apiHandler({
  "DELETE": removeTrace,
  GET,
  async PATCH(req, res) {
    res.status(200).json({ ok: true });
  },
});
