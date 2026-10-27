<?php

namespace App\Http\Controllers\Concerns;

use Illuminate\Support\Facades\Auth;

trait LocksIndex
{
    public function index()
    {
        abort_if(! Auth::check(), 403);

        return 'locked';
    }
}
