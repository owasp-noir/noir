import asyncHandler from '../utils/async-handler.js';

class ForbiddenError extends Error {}

export const handler = async (req: any, _res: any, next: any) => {
	if (!req.accountability?.admin) {
		throw new ForbiddenError();
	}

	return next();
};

export default asyncHandler(handler);

// Refuses share links, lets an anonymous caller through.
export const noShares = (req: any, _res: any, next: any) => {
	if (req.accountability?.share) throw new ForbiddenError();
	return next();
};
