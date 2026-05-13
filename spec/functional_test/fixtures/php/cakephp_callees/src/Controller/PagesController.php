<?php

namespace App\Controller;

class PagesController extends AppController
{
    public function home()
    {
        $payload = PageService::home();
        return $this->renderHome($payload);
    }
}
