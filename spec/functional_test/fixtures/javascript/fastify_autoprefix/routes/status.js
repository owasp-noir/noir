// `autoPrefix` sets this plugin's prefix; the route is served at
// `/_app/status`.
export const autoPrefix = '/_app';

export default async function (fastify) {
  fastify.get('/status', async () => ({ status: 'ok' }));
}
