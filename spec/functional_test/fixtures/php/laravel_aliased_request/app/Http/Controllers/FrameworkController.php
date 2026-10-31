<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;

class FrameworkController
{
    public function store(Request $request)
    {
        return $request->input('plain');
    }
}
