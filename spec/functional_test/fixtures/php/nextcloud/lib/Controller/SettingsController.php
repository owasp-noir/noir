<?php

namespace OCA\Notes\Controller;

use OCA\Notes\Settings\Admin;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http\Attribute\AuthorizedAdminSetting;
use OCP\AppFramework\Http\Attribute\FrontpageRoute;
use OCP\AppFramework\Http\JSONResponse;

class SettingsController extends Controller
{
    #[AuthorizedAdminSetting(settings: Admin::class)]
    #[FrontpageRoute(verb: 'POST', url: '/settings')]
    public function set(string $defaultFolder): JSONResponse
    {
        return new JSONResponse([]);
    }
}
