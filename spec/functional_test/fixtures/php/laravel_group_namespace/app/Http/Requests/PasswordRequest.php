<?php

namespace App\Http\Requests;

use App\Support\ReadsInput;
use Illuminate\Foundation\Http\FormRequest;

class PasswordRequest extends FormRequest
{
    use ReadsInput;

    public function getAll(): array
    {
        return ['current' => $this->readString('current'), 'page' => $this->query('page')];
    }

    public function rules(): array
    {
        return [
            'current' => 'required',
            'page'    => 'integer',
            'new'     => 'required|confirmed',
        ];
    }
}
