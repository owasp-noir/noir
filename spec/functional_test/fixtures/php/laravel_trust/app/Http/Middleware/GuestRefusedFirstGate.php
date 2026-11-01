<?php

namespace App\Http\Middleware;

use Closure;

// The guest is refused before the pass-through, so this stays an auth guard.
class GuestRefusedFirstGate
{
    public function handle($request, Closure $next)
    {
        if (! $request->user()) {
            abort(401);
        }
        if (! $request->user()->active) {
            return $next($request);
        }

        return $next($request);
    }
}
