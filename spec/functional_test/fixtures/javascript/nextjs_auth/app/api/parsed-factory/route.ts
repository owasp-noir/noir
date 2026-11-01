import { z } from 'zod';
import { parseRequest } from '../../../lib/request';
import { auditedSchema, withPaging } from '../../../lib/schema';

export async function GET(request: Request) {
  if (process.env.CLOUD_MODE) {
    return new Response(null, { status: 404 });
  }

  const schema = withPaging({ q: z.string() });

  const { auth, error } = await parseRequest(request, schema);

  if (error) {
    return error();
  }

  return Response.json(auth);
}

export async function POST(request: Request) {
  const schema = auditedSchema(request);

  const { auth, error } = await parseRequest(request, schema);

  if (error) {
    return error();
  }

  return Response.json(auth);
}
