export default async function (app) {
  app.get('/elsewhere', { config: { level: 2 } }, async () => 'ok')
  app.get('/sibling', { config: { tier: 'gold' } }, async () => 'ok')
  app.get('/vip', { config: { vip: true } }, async () => 'ok')
}
