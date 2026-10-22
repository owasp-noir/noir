import express from 'express';

Deno.test('app', () => {
  const app = express();
  app.get('/phantom-deno', (req, res) => res.end());
});
