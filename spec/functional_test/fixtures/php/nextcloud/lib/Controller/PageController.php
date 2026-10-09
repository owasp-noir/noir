<?php

namespace OCA\Notes\Controller;

use OCP\AppFramework\Controller;
use OCP\AppFramework\Http\Attribute\FrontpageRoute;
use OCP\AppFramework\Http\Attribute\NoAdminRequired;
use OCP\AppFramework\Http\Attribute\NoCSRFRequired;
use OCP\AppFramework\Http\TemplateResponse;

class PageController extends Controller
{
    // #[PublicPage]
    #[NoAdminRequired]
    #[NoCSRFRequired]
    public function index(): TemplateResponse
    {
        $renderer = new class {
            public function index($secret) {}
        };
        return new TemplateResponse('notes', 'main');
    }

    // #[FrontpageRoute(verb: 'GET', url: '/removed')]
    public function removed() {}
}
