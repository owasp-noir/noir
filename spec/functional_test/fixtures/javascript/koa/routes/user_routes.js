const Router = require('koa-router');
const router = new Router();

router.get('/users', ctx => {
  ctx.body = [{ id: 1, name: 'User1' }];
});

router.post('/users', ctx => {
  // const { name, email } = ctx.request.body;
  ctx.body = 'User created';
  ctx.status = 201;
});

router.get('/users/:id', ctx => {
  // const id = ctx.params.id;
  ctx.body = { id: ctx.params.id, name: `User ${ctx.params.id}` };
});

module.exports = router;
