import { json } from '@sveltejs/kit';

export async function PUT({ params, request }) {
  const body = await request.json();
  await updateUser(params.id, body);
  AuditLog.write('svelte:update');

  return json({ id: params.id });
}

const deleteUser = async ({ params }) => {
  await deleteUserById(params.id);
  return json({ deleted: true });
};

export { deleteUser as DELETE };
