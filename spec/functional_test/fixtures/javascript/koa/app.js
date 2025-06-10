const Koa = require('koa');
const Router = require('koa-router');
const userRoutes = require('./routes/user_routes');
const apiV1Routes = require('./routes/api_v1');
const adminRoutes = require('./routes/admin_routes');
const appRouter = require('./routes/app_router');

const app = new Koa();
const router = new Router();

app.use(router.routes());
app.use(userRoutes.routes());
app.use('/api/v1', apiV1Routes.routes());
app.use(adminRoutes.routes()); // adminRoutes has prefix defined in itself
app.use('/app_prefix', appRouter.routes());


// Simple route on app
app.get('/simple', ctx => {
  ctx.body = 'Simple GET';
});

router.del('/items/:itemId', ctx => {
  // Should be detected as DELETE
  ctx.body = `Deleted item ${ctx.params.itemId}`;
});

app.all('/everything', ctx => {
    ctx.body = 'Handles all methods';
});

app.listen(3000);
