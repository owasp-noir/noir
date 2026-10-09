<?php

namespace OCA\Notes\Controller;

use OCP\AppFramework\Http\DataResponse;
use OCP\AppFramework\OCSController;

class ApiController extends OCSController
{
    /**
     * @PublicPage
     * @NoCSRFRequired
     */
    public function share(string $shareWith, int $permissions = 1): DataResponse
    {
        return new DataResponse([]);
    }
}
