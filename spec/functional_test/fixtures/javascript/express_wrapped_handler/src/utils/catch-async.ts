import type { RequestHandler } from 'express';

export function catchAsync<T extends RequestHandler>(
	fn: T,
) {
	return async function wrapped(
		req: any,
		res: any,
		next: any,
	) {
		try {
			await fn(req, res, next);
		} catch (err) {
			next(err);
		}
	};
}

// Refuses on its own before handing the request on: a guard around `fn`.
export const withAuth = (fn: RequestHandler) => (req: any, res: any, next: any) =>
	req.user ? fn(req, res, next) : res.sendStatus(401);
