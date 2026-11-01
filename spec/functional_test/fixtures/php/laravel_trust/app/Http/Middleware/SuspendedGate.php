<?php

namespace App\Http\Middleware;

use Closure;

// Refuses only a signed-in suspended user: a guest is never refused, so no auth guard.
class SuspendedGate
{
    public function handle($request, Closure $next)
    {
        if (($request->user()) && ($request->user()->suspended)) {
            return response()->json(['error' => 'suspended'], 403);
        }

        return $next($request);
    }
}
