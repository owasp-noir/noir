import { z } from 'zod';
import { parseLogin, parseRequest } from '../../../lib/request';
import { json, unauthorized } from '../../../lib/response';

export async function GET(request: Request) {
  const schema = z.object({
    page: z.number(),
  });

  const { auth, error } = await parseRequest(request, schema);

  if (error) {
    return error();
  }

  return json(auth.user);
}

export async function POST(request: Request) {
  const { error } = await parseRequest(request, null, { skipAuth: true });

  if (error) {
    return error();
  }

  return json({ ok: true });
}

export async function PUT(request: Request) {
  const { auth, error } = await parseLogin(request);
  if (error) return error();
  return json(auth);
}

// The result is dropped: nothing hands the refusal on.
export async function PATCH(request: Request) {
  const { auth } = await parseRequest(request);
  return json(auth);
}

export async function DELETE(request: Request) {
  const session = await getSession();
  if (!session) {
    return unauthorized();
  }
  return json({ deleted: true });
}
