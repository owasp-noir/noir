// No autoPrefix and dirNameRoutePrefix is false, so the `redirect/`
// directory does NOT add a prefix — this is served at `/go`, not
// `/redirect/go`.
export default async function (fastify) {
  fastify.get('/go', async (request, reply) => reply.redirect('/'));
}
