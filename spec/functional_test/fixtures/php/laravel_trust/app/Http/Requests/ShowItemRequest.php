<?php

namespace App\Http\Requests;

use App\Http\Requests\Concerns\ValidatesFolder;
use Illuminate\Foundation\Http\FormRequest;

class ShowItemRequest extends FormRequest
{
    use ValidatesFolder;

    public function rules(): array
    {
        return [
            'q' => ['string'],
            ...$this->folderRules(),
        ];
    }
}
