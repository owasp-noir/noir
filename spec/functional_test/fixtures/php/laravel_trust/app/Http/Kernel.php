<?php

namespace App\Http;

use App\Http\Middleware\TokenGate;
use Illuminate\Foundation\Http\Kernel as HttpKernel;

class Kernel extends HttpKernel
{
    protected $middlewareGroups = [
        'web' => [
            \App\Http\Middleware\Localize::class,
        ],
        'api' => [
            'throttle:api',
            TokenGate::class,
        ],
    ];
}
