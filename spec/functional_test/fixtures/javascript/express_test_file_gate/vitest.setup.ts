import { createTestHttpServer } from '@epic-web/test-server/http';

export default async function setup() {
  return createTestHttpServer({
    defineRoutes(router) {
      router.post('/phantom-test-server', () => new Response(null, { status: 200 }));
    },
  });
}
