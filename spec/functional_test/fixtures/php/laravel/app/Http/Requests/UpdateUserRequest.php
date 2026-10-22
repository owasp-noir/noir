<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class UpdateUserRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'nickname' => 'required|string',
            'bio' => ['nullable', 'max:500'],
        ];
    }

    public function messages(): array
    {
        return [
            'nickname.required' => 'A nickname is required',
        ];
    }
}
