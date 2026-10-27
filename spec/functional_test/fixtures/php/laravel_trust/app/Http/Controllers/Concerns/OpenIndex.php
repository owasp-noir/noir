<?php

namespace App\Http\Controllers\Concerns;

trait OpenIndex
{
    public function index()
    {
        return 'open';
    }
}
