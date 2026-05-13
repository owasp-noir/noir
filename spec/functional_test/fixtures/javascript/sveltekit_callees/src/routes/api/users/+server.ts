import { json, type RequestHandler } from '@sveltejs/kit';

export const GET: RequestHandler = async ({ url }) => {
  const page = url.searchParams.get('page');
  const users = await listUsers(page);
  AuditLog.write('svelte:list');

  return json(serializeUsers(users));
};

export const POST: RequestHandler = async ({ request }) => {
  const body = await request.json();
  await serviceFactory().create(body);
  AuditLog.write('svelte:create');

  return json({ ok: true });
};
