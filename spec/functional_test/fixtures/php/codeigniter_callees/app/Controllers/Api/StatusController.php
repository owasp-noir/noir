<?php

namespace App\Controllers\Api;

use App\Controllers\BaseController;

class StatusController extends BaseController
{
    public function index()
    {
        $status = StatusProbe::check();
        return $this->response->setJSON(['status' => $status]);
    }
}
