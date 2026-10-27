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

    protected $middlewareAliases = [
        'staff' => \App\Http\Middleware\Staff::class,
        'guest' => \App\Http\Middleware\Guest::class,
        'guestonly' => \App\Http\Middleware\GuestOnly::class,
    ];
}
