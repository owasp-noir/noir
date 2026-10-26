'use strict';

const helpers = require('./helpers');

// `controllers` is the module routes/index.js hands in.
module.exports = function (app, controllers) {
	app.get('/feed/:tid.rss', helpers.tryRoute(controllers.write.posts.feed));
};
