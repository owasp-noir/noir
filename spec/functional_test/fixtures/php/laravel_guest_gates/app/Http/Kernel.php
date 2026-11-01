<?php
namespace App\Http;
use Illuminate\Foundation\Http\Kernel as HttpKernel;
class Kernel extends HttpKernel
{
    protected $middlewareGroups = [
        'web' => [ \Illuminate\Session\Middleware\StartSession::class ],
        'api' => [],
    ];
    protected $middlewareAliases = [
        'api.ip' => \App\Http\Middleware\NestedPass::class,
        'auth' => \App\Http\Middleware\Authenticate::class,
    ];
}
