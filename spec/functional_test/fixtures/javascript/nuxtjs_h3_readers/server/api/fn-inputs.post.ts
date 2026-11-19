export default defineEventHandler(async (event) => {
  const auth = event.headers.get("authorization");
  const legacy = event.node.req.headers["x-legacy"];
  const all = getRequestHeaders(event);
  const tenant = all["x-tenant"];
  const jar = parseCookies(event);
  const sid = jar.sid;
  const debug = getRequestURL(event).searchParams.get("debug");
  const form = await readFormData(event);
  const title = form.get("title");
  return { auth, legacy, tenant, sid, debug, title };
});
