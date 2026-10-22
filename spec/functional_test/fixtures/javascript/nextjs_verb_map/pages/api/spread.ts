import { apiHandler } from "../../lib/api-handler";
import { base } from "../../lib/base";

// A spread may bring more verbs than the literal shows: no narrowing.
export default apiHandler({
  ...base,
  GET: async (req, res) => {
    res.status(200).json({ ok: true });
  },
});
