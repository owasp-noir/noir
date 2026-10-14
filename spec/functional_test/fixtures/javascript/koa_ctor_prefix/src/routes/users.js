const Router = require('@koa/router');
const router = new Router();

router
  .get('/', async (ctx) => {
    const { page } = ctx.query;
    ctx.body = [];
  })
  .get('/:id', async (ctx) => {
    ctx.body = { id: ctx.params.id };
  })
  .post('/', async (ctx) => {
    const { name } = ctx.request.body;
    ctx.body = { name };
  });

module.exports = router;
