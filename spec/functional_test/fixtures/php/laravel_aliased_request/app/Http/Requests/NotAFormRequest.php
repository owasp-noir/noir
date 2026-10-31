<?php

namespace App\Http\Requests;

// Named like a request but not a FormRequest: its keys are not request params.
class NotAFormRequest
{
    public function rules(): array
    {
        return ['bogus' => 'x'];
    }
}
