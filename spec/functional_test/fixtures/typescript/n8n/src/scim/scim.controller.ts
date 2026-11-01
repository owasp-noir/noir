import { Get, Param, Put, RootLevelController } from '@n8n/decorators';

import { scimDiscoveryRoute, scimRoute } from './scim-route';

@RootLevelController('/scim/v2')
export class ScimController {
	@Put('/Users/:id', scimRoute)
	async replaceUser(@Param('id') id: string) {
		return id;
	}

	@Get('/ServiceProviderConfig', scimDiscoveryRoute)
	async serviceProviderConfig() {
		return {};
	}
}
