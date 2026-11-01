import { RestController, Get, Post, GlobalScope, Body, Param, Query } from '@n8n/decorators';
import { commentedOpts, strOpts, openOpts } from './opts/route-opts';
import { openOpts as barrelOpts } from './opts';

const localCommented = {
	/* skipAuth: true */
	ipRateLimit: true,
};
const spreadBase = { skipAuth: true };
const isDev = process.env.DEV === '1';
const SCOPE = 'user:list';
const middlewares = [cookieParser()];

@RestController('/a')
export class AController {
	@Get('/false', { skipAuth: false })
	f() {}

	@Get('/isdev', { skipAuth: isDev })
	d() {}

	@Get('/spread', { ...spreadBase })
	s() {}

	@Get('/imported-commented', commentedOpts)
	ic() {}

	@Get('/local-commented', localCommented)
	lc() {}

	@Get('/imported-str', strOpts)
	is() {}

	@Get('/barrel-open', barrelOpts)
	bo() {}

	@Get('/direct-open', openOpts)
	dop() {}

	@Get('/preview', { allowSkipPreviewAuth: true })
	pv() {}

	@Get('/multiline', {
		ipRateLimit: true,
		skipAuth:
			true,
	})
	ml() {}

	@Get('/neg', { skipAuth: !isDev })
	neg() {}

	@GlobalScope(SCOPE)
	@Get('/scope-const', { skipAuth: true })
	sc() {}

	@Get('/oauth-cb', { skipAuth: true, middlewares: [oauthCallbackLogger] })
	ocb() {}

	@Get('/nested', { cors: { skipAuth: true } })
	nst() {}

	@Post('/allow-false', { allowUnauthenticated: false, skipAuth: false })
	af() {}

	@Post('/dynamic', { allowUnauthenticated: true, middlewares: getDynamicCredentialMiddlewares() })
	dyn() {}

	@Post('/own-auth', { skipAuth: true, middlewares: [logRequests, getAuthMiddleware()] })
	own() {}

	@Get('/sign-in', { skipAuth: true, middlewares })
	signIn() {}
}
