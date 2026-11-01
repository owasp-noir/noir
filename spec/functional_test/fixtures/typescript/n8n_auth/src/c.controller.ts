import { RestController, Get } from '@n8n/decorators';

// const legacyOpts = { skipAuth: true };
const legacyOpts = { ipRateLimit: true };

const lineCommented = {
	// skipAuth: true, // TODO re-enable once SSO lands
	ipRateLimit: true,
};

@RestController('/c')
export class CController {
	@Get('/legacy', legacyOpts)
	l() {}

	@Get('/line-commented', lineCommented)
	lc() {}
}
