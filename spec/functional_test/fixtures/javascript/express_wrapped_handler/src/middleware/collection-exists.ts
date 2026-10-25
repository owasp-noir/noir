import asyncHandler from '../utils/async-handler.js';

class ForbiddenError extends Error {}

// Refuses an unknown collection, whoever asks: request data, not a guard.
export default asyncHandler(async (req: any, _res: any, next: any) => {
	if (!req.schema.collections[req.params.collection]) {
		throw new ForbiddenError();
	}
	return next();
});
