<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Auth\AuthenticationException;

class Authenticate
{
    public function handle($request, Closure $next)
    {
        if (!auth()->check()) {
            throw new AuthenticationException('Unauthenticated.');
        }

        return $next($request);
    }
}
