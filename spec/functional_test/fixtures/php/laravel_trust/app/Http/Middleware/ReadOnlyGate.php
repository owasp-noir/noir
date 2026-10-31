<?php

namespace App\Http\Middleware;

use Closure;

// Refuses every caller (signed in or not) while the app setting is on: no auth guard.
class ReadOnlyGate
{
    public function handle($request, Closure $next)
    {
        if (! config('app.read_only')) {
            return $next($request);
        }

        return response()->json(['error' => true], 401);
    }
}
