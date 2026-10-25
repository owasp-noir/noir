<?php

namespace App\Http\Controllers;

use App\Http\Requests\PasswordRequest;
use Illuminate\Http\Request;

class AccountController
{
    public function index(Request $request)
    {
        return view('account', ['email' => $request->email]);
    }

    public function password(PasswordRequest $request)
    {
        return $request->getAll();
    }
}
