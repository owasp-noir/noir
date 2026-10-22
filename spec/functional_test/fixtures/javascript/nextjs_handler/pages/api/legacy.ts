import { defaultHandler, defaultResponder } from "../../lib/responder";

const getHandler = async (req, res) => {
  return { ok: true };
};

export default defaultHandler({
  GET: Promise.resolve({ default: defaultResponder(getHandler) }),
  POST: import("./_post"),
});
