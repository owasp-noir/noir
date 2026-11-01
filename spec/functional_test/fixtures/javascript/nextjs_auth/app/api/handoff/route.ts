import { parseRequest } from '../../../lib/request';
import { authenticateUser, createSession, getAuthenticatedUser, parseSplit } from '../../../lib/options';
import { checkAuth } from '../../../lib/session';
import { json, unauthorized } from '../../../lib/response';

// the `if` after the call reads another field and hands nothing on.
export async function GET(request: Request) {
  const { query, error } = await parseRequest(request);
  if (query.ping) {
    return json({ ok: true });
  }
  return json(await db.secrets());
}

// the 401 is in `authError`; only the validation `error` is handed on.
export async function POST(request: Request) {
  const { auth, error } = await parseSplit(request, schema);
  if (error) return error();
  return json(1);
}

// a login helper given the request.
export async function PUT(request: Request) {
  const user = await authenticateUser(request);
  if (!user) {
    return unauthorized();
  }
  return json({ token: sign(user) });
}

// the 401 sits in the `else if` of an `if (!auth)` that logs.
export async function PATCH(request: Request) {
  const auth = await checkAuth(request);
  if (!auth) {
    console.log('anonymous');
  } else if (auth.user.banned) {
    return unauthorized();
  }
  return json(1);
}

// a schema parse of an awaited write before the helper.
export async function DELETE(request: Request) {
  const data = z.object({ a: z.string() }).parse(await saveUpload(request));
  const { error } = await parseRequest(request);
  if (error) return error();
  return json(1);
}

// a deployment switch that serves data, before the helper.
export async function HEAD(request: Request) {
  if (process.env.DEMO_MODE) {
    return json(await db.allUsers());
  }
  const { error } = await parseRequest(request);
  if (error) return error();
  return json(1);
}

// the helper's own field handed on.
export async function OPTIONS(request: Request) {
  const { error: denied } = await parseRequest(request);
  if (denied) return denied();
  return json(1);
}

// A login helper that starts a session.
export async function first(request: Request) {
  const created = await createSession(request);
  if (!created) {
    return unauthorized();
  }
  return json(1);
}

// A check of a middleware-set header.
export async function second() {
  const user = await getAuthenticatedUser();
  if (!user) {
    return unauthorized();
  }
  return json(1);
}
