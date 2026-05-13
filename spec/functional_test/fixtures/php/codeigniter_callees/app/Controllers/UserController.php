<?php

namespace App\Controllers;

class UserController extends BaseController
{
    public function show($id)
    {
        $user = UserRepository::find($id);
        return $this->response->setJSON($user);
    }
}
