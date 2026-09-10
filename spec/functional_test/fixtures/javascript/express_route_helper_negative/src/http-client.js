'use strict';

// Every function here forwards a caller-supplied path to a
// caller-supplied receiver. None of them registers a route.

// Verb and URL both arrive as arguments, dispatched through a computed
// member — the shape a route helper uses, on an HTTP client.
exports.request = function (client, method, url) {
	return client[method](url, { timeout: 5000 });
};

exports.fetchJson = function (client, url) {
	return client.get(url, { json: true });
};

exports.readCache = function (cache, key) {
	return cache.get(key, null);
};

exports.dispatch = function (handlers, event, payload) {
	return handlers[event](payload, { async: true });
};

// `use` is not a verb, so mounting through a helper mints nothing either.
exports.mountAt = function (app, prefix, child) {
	app.use(prefix, child);
};
