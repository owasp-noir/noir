import { ApiKeyScope, Get, Param, PublicApiController, Query } from '@n8n/decorators';

// The public API registry authenticates every route, whatever its options.
@PublicApiController('/tags')
export class TagsPublicController {
	@Get('/')
	@ApiKeyScope('tag:list')
	async getTags(@Query query: TagsListQuery) {
		return query;
	}

	@Get('/:tagId', { skipAuth: true })
	async getTag(@Param('tagId') tagId: string) {
		return tagId;
	}
}
