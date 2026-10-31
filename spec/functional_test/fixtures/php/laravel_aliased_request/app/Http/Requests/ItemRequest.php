<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class ItemRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'name' => 'required|string',
            'sale_price' => 'nullable',
        ];
    }
}
