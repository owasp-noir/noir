<?php

namespace App\Http\Controllers;

use App\Http\Requests\NotAFormRequest as Request;

class PlainController
{
    public function store(Request $request)
    {
        return 'ok';
    }
}
