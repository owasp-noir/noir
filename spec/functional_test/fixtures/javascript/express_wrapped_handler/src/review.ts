import express from 'express';
import { catchAsync, withAuth } from './utils/catch-async.js';
import checkIsAdmin, { noShares } from './middleware/is-admin.js';
import collectionExists from './middleware/collection-exists.js';
import { ThingsService } from './services/things.js';

const app = express();

const adminOnly = async (req: any, res: any, next: any) => {
	if (!req.user?.admin) return res.sendStatus(403);
	next();
};
const list = (req: any, res: any) => res.json({ q: req.query.q });

// A wrapped guard in a middleware position is still judged as one.
app.get('/r/admin', catchAsync(adminOnly), list);
// A refusing wrapper is the guard; the function it wraps is the handler.
app.get('/r/authed', withAuth(list));
// Definition-judged: throws on who the caller is vs. on request data.
app.get('/r/schema', checkIsAdmin, list);
app.get('/r/items/:collection', collectionExists, list);
app.get('/r/shared', noShares, list);

// Request data and local variables are not the caller.
app.get('/r/users/:userId/posts', async (req: any, res: any) => {
	if (!req.params.userId) throw new Error('userId required');
	res.json({});
});
app.post('/r/requests/:id/accept', async (req: any, res: any) => {
	const request = await findRequest(req.params.id);
	if (!request.userId) throw new Error('not found');
	res.json(request);
});
// A status without a response falls through.
app.get('/r/leak', async (req: any, res: any) => {
	if (!req.user) res.status(401);
	res.json({ secret: 1 });
});

// A service built from request data or a fixed identity is not the caller.
app.get('/r/users/:userId/things', async (req: any, res: any) => {
	const service = new ThingsService({ accountability: req.params.userId });
	const thing = await service.readMine(req.params.userId);
	res.json(thing);
});
app.get('/r/stats', async (req: any, res: any) => {
	const service = new ThingsService({ accountability: { user: 'system' } });
	const thing = await service.readMine('stats');
	res.json(thing);
});

// A pass-through before a handler that reads res.locals is not the handler.
const noCache = (req: any, res: any, next: any) => {
	res.set('Cache-Control', 'no-store');
	next();
};
const showProfile = (req: any, res: any) => res.json({ user: res.locals.user });
app.get('/r/me', noCache, showProfile);
app.get('/r/profile', noCache, showProfile);

// A path mount written over several lines keeps its path.
app.use(
	'/r/private',
	adminOnly,
);
app.get('/r/private/a', (req: any, res: any) => res.json({}));
app.get('/r/open', (req: any, res: any) => res.json({}));

declare function findRequest(id: string): Promise<any>;
export default app;
