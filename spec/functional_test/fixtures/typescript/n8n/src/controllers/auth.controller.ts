import { Body, Get, Post, Query, RestController } from '@n8n/decorators';
import type { Response } from 'express';

import { LoginRequestDto } from '../dto/login.dto';

// `skipAuth: true` in a comment or a string must not open a route:
// @Get('/commented', { skipAuth: true })
@RestController()
export class AuthController {
	constructor(private readonly authService: AuthService) {}

	/** Log in — the cookie is not checked on the way in. */
	@Post('/login', {
		skipAuth: true,
		ipRateLimit: { limit: 1000 },
	})
	async login(req: AuthlessRequest, res: Response, @Body payload: LoginRequestDto) {
		return await this.authService.login(payload);
	}

	// Explicitly guarded: `false` is the default, not an opening.
	@Get('/me', { skipAuth: false })
	async me(req: AuthenticatedRequest) {
		return req.user;
	}

	@Get('/describe', { summary: 'skipAuth: true is not set here' })
	async describe() {
		return 'ok';
	}

	// A setting decides: still reported, with the setting named.
	@Get('/resolve-signup-token', { skipAuth: config.publicSignup })
	async resolveSignupToken(req: AuthlessRequest, @Query query: ResolveQuery) {
		return query;
	}

	@Get('/préférences', { allowUnauthenticated: true })
	async preferences() {
		return 'é';
	}
}
