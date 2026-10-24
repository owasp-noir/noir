<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Auth\AuthenticationException;

class TokenGate
{
    public function handle($request, Closure $next)
    {
        $this->ensureToken($request);

        return $next($request);
    }

    protected function ensureToken($request): void
    {
        if (!$request->bearerToken()) {
            throw new AuthenticationException('Unauthenticated.');
        }
    }
}
