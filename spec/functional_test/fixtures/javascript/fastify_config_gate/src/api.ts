export default async function (app) {
  app.get('/admin', { config: { permissions: ['manage:system'] } }, async () => 'ok')
  app.get('/none', { config: { permissions: [] } }, async () => 'ok')
  app.get('/public', { config: { publicAccess: true } }, async () => 'ok')
  app.get('/plain', async () => 'ok')
}
