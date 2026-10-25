import express from 'express';
import asyncHandler from './utils/async-handler.js';
import { allow, respond } from './middleware/respond.js';
import { ThingsService } from './services/things.js';

class InvalidCredentialsError extends Error {}

const router = express.Router();

const readHandler = asyncHandler(async (req, res, next) => {
	res.locals['payload'] = { data: req.query.q };
	return next();
});

router.get('/items', readHandler, respond);

router.get(
	'/random',
	asyncHandler(async (req, res) => {
		return res.json({ data: req.query.length });
	}),
);

router.post(
	'/sort',
	asyncHandler(async (req, res, next) => {
		res.locals['payload'] = req.body.item;
		return next();
	}),
	respond,
);

// Reads res.locals but serves only this route: it is the handler.
const loadUser = (req: any, res: any, next: any) => {
	res.locals.user = req.query.id;
	next();
};
const showMe = (req: any, res: any) => {
	res.json(res.locals.user);
};

router.get('/me', loadUser, showMe);

// The handler refuses a caller without a user before doing anything else.
router.patch(
	'/me/page',
	asyncHandler(async (req, res, next) => {
		if (!req.accountability?.user) {
			throw new InvalidCredentialsError();
		}
		res.locals['payload'] = req.body.page;
		return next();
	}),
	respond,
);

// One hop: the service method it awaits opens with the same refusal.
router.get(
	'/things/:id/mine',
	asyncHandler(async (req, res) => {
		const service = new ThingsService({ accountability: req.accountability });
		const thing = await service.readMine(req.params.id);
		return res.json(thing);
	}),
);

// Not guards: an anonymous caller passes, or reaches a response first.
router.get(
	'/things/:id',
	asyncHandler(async (req, res, next) => {
		if (!req.user) return next();
		const service = new ThingsService({ accountability: req.accountability });
		return res.json(await service.readPublic(req.params.id));
	}),
);

router.get(
	'/cached',
	asyncHandler(async (req, res) => {
		if (req.query.cached) return res.json({ cached: true });
		if (!req.user) throw new InvalidCredentialsError();
		return res.json({});
	}),
);

router.get(
	'/staff',
	asyncHandler(async (req, res) => {
		if (req.user && !req.user.admin) throw new InvalidCredentialsError();
		return res.json({});
	}),
);

const isJson = (req: any) => req.is('json');

router.post('/checked', allow(isJson));

export default router;
