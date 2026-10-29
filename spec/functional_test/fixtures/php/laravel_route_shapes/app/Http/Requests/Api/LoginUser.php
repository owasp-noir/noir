<?php

namespace App\Http\Requests\Api;

use Illuminate\Foundation\Http\FormRequest;

class LoginUser extends FormRequest
{
    public function rules()
    {
        return ['email' => 'required|email', 'password' => 'required'];
    }
}
