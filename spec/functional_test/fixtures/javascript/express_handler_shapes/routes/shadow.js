// `controllers` is bound by the caller here, but rebound in `inner`.
module.exports = function (app, controllers) {
	app.get('/shadow/outer', controllers.posts.list);
	function inner(router, controllers) {
		router.get('/shadow/inner', controllers.posts.list);
	}
	inner(app, require('../meta'));
};
