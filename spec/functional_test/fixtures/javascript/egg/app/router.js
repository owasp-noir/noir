'use strict';

/**
 * @param {Egg.Application} app - egg application
 */
module.exports = app => {
  const { router, controller, middleware } = app;
  const auth = middleware.auth();

  router.get('/', controller.home.index);
  router.get('/api/users/:id', controller.user.show);
  router.post('login', '/api/login', auth, 'user.login');
  router.del('/api/users/:id', controller.user.destroy);
  router.resources('posts', '/api/posts', controller.posts);
  router.resources('/api/tags', controller.tags);
  // router.get('/legacy', controller.home.legacy);
  router.redirect('/home', '/', 302);
  router.get('/health', async ctx => {
    ctx.body = { ok: true, verbose: ctx.query.verbose };
  });

  require('./router/admin')(app);
};
