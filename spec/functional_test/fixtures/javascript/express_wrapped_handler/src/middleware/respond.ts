import asyncHandler from '../utils/async-handler.js';

// Renders whatever the step before it left on res.locals, for every route.
export const respond = asyncHandler(async (req, res) => {
	if (req.query.export) return res.attachment('export.json').send(res.locals['payload']);
	return res.json(res.locals['payload']);
});

// Consults its argument; it does not hand the request to it.
export const allow = (check: (req: any) => boolean) => (req: any, res: any, next: any) =>
	check(req) ? next() : res.sendStatus(400);
