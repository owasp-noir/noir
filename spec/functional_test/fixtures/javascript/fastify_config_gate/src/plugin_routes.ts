export default async function (app) {
  app.get('/elsewhere', { config: { level: 2 } }, async () => 'ok')
}
