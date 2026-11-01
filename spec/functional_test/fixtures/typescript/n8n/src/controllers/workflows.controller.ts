import { Delete, Get, GlobalScope, Param, Patch, ProjectScope, RestController } from '@n8n/decorators';

@RestController('/workflows')
export class WorkflowsController {
	@Get('/:workflowId')
	@ProjectScope('workflow:read')
	async getWorkflow(req: AuthenticatedRequest, _res: Response, @Param('workflowId') workflowId: string) {
		return workflowId;
	}

	// A one-line member must not hand its options to the next one.
	@Get('/public-ping', { skipAuth: true }) ping() { return 'pong'; }

	@Patch('/:workflowId')
	async update(@Param('workflowId') workflowId: string) {
		return workflowId;
	}

	@Delete('/:workflowId', { skipAuth: true })
	@GlobalScope('workflow:delete')
	async remove(@Param('workflowId') workflowId: string) {
		return workflowId;
	}
}
