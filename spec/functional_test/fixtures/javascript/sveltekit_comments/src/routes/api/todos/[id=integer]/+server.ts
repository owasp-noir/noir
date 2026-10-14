import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ params, url }) => {
  const limit = url.searchParams.get('limit');
  return json({ id: params.id, limit });
};

// TODO: re-enable once soft-delete lands
// export const DELETE: RequestHandler = async ({ params }) => {
//   return new Response(null, { status: 204 });
// };

/*
export async function PUT({ request }) {}
*/
