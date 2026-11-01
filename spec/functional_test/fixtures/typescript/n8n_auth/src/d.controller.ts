import { RestController, Get } from '@n8n/decorators';

@RestController('/d')
export class DController {
	@Get('/public', { skipAuth: true })
	@Get('/private')
	both() {}
}
