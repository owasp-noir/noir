import { text } from '@sveltejs/kit';

export async function GET() {
  return text('get');
}

export async function fallback({ request }) {
  return text(`I caught your ${request.method} request!`);
}
