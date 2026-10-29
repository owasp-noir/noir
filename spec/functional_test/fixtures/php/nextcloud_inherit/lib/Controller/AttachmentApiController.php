<?php

namespace OCA\Deck\Controller;

use OCP\AppFramework\ApiController;
use OCP\AppFramework\Http\Attribute\NoAdminRequired;
use OCP\AppFramework\Http\Attribute\NoCSRFRequired;

class AttachmentApiController extends ApiController {
	#[NoAdminRequired]
	#[NoCSRFRequired]
	public function display(int $attachmentId, string $type = 'file') {
		return $this->attachmentService->display($attachmentId, $type);
	}
}
