const express = require('express');
const meta = require('./meta');
const controllers = require('./controllers');

const app = express();
const router = express.Router();

// The wrapper calls its SECOND argument with the request.
function wrap2(onErr, fn) {
	return async (req, res, next) => {
		try { await fn(req, res, next); } catch (e) { onErr(e, req, res); }
	};
}
function logErr(e, req, res) { res.status(500).json({ e: String(e) }); }
async function real(req, res) { res.json({ q: req.query.q }); }
app.get('/wrap', wrap2(logErr, real));

// A helper forwarding a guard passed before the path.
function ensureAuthenticated(req, res, next) {
	if (!req.user) return res.status(401).json({ e: 'login' });
	next();
}
function secured(guard, router, verb, path, controller) {
	router[verb](path, guard, controller);
}
secured(ensureAuthenticated, router, 'get', '/secret', real);

// Guests refused only when a setting says so, or only for writes.
function maybePrivate(req, res, next) {
	if (!req.user) {
		if (meta.privateSite) {
			return res.status(401).json({ e: 'login' });
		}
	}
	next();
}
function writesNeedLogin(req, res, next) {
	if (!req.user) {
		if (req.method !== 'GET') return res.sendStatus(401);
	}
	next();
}
app.get('/maybe', maybePrivate, real);
app.get('/reads', writesNeedLogin, real);
app.post('/reads', writesNeedLogin, real);

// An array emptied after it is written down.
const mws = [ensureAuthenticated];
const open = [...mws];
open.splice(0, 1);
app.get('/opened', [...open], real);

// What a handler hands its request to: a write and a destructured record are not reads.
function setDefaults(req) { req.body.sort = 'asc'; return req.query.page; }
async function fromRemote({ session }, client) { return client.body.items; }
function defaults(req, res) { setDefaults(req); fromRemote(req, {}); res.json({}); }
app.get('/defaults', defaults);

// Answers through the request, passes on otherwise: still the handler.
function show(req, res, next) {
	if (!req.params.id) return next();
	reply(req);
}
function reply(req) { req.res.json({}); }
app.get('/items/:id', show);

app.get('/posts', controllers.posts.list);
app.get('/spread', controllers.spread.list);
app.get('/over', controllers.over.thing);

require('./routes/shadow')(app, controllers);

// A bare name in its own file is the local function, not the export of that name.
const Shapes = module.exports;
Shapes.install = async function (port) { return port; };
async function install(req, res) { res.json({ ok: req.body.ok }); }
app.post('/install', install);

app.use(router);
app.listen(3000);
