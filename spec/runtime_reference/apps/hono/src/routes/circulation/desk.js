import { Hono } from 'hono';
import { createFactory } from 'hono/factory';

const factory = createFactory();

export function createDesk(branch) {
  const desk = new Hono().basePath('/circulation');
  const loan = factory.createHandlers(
    async (c, next) => { c.header('X-Branch', branch); await next(); },
    c => c.json({ branch, loan: c.req.param('id') })
  );
  desk.get('/loans', c => c.json({ branch, loans: [] }));
  desk.post('/loans', c => c.text('Checked out', 201));
  desk.get('/loans/:id', ...loan);
  desk.post('/loans/:id/renew', ...loan);
  desk.delete('/loans/:id', c => c.body(null, 204));
  desk.get('/holds', c => c.json({ branch, holds: [] }));
  desk.post('/holds', c => c.text('Reserved', 201));
  desk.delete('/holds/:id', c => c.body(null, 204));
  desk.get('/hours', c => c.json({ branch, opens: '09:00' }));
  return desk;
}
