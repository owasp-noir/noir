import type { RequestHandler } from 'express';

const scimAuth = () => (req, res, next) => (req.headers.authorization ? next() : res.status(401).end());

export const scimRoute: {
	skipAuth: boolean;
	middlewares: RequestHandler[];
} = {
	skipAuth: true,
	middlewares: [scimOptInGate, scimAuth()],
};

export const scimDiscoveryRoute = {
	skipAuth: true,
	middlewares: [scimOptInGate, isScimEnabledMiddleware, logTokenFailures],
};
