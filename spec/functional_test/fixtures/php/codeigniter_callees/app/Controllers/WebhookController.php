<?php

namespace App\Controllers;

class WebhookController extends BaseController
{
    public function any()
    {
        WebhookHandler::dispatch();
        return $this->response->setJSON(['ok' => true]);
    }
}
