<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StorePhotoRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // Typically some logic here
    }

    public function rules(): array
    {
        return [
            'title' => 'required|string|max:255',
            'image_file' => 'required|file|mimes:jpg,png',
        ];
    }
}
