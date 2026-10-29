<?php

namespace App\Http\Controllers\Api;

use App\Http\Requests\Api\LoginUser;

class AuthController extends Controller
{
    public function login(LoginUser $request)
    {
        $credentials = $request->only('user.email', 'user.password');
        $rest = $request->except(['user.remember', 'user.token']);
        return $credentials;
    }
}
