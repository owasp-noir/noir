import express from 'express';
import request from 'supertest';

const buildApp = () => {
  const app = express();
  app.use('/api', (req, res) => {
    res.status(200).json({ userId: req.session?.user?.id ?? null });
  });
  return app;
};

test('keeps the session alive', async () => {
  await request(buildApp()).get('/api').expect(200);
});
