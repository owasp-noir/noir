<?php

namespace App\Http\Middleware;

use Closure;

// A guest returns early; the 403 below only reaches signed-in users.
class GuestPassGate
{
    public function handle($request, Closure $next)
    {
        $user = $request->user();
        if (! $user || $user->two_factor_confirmed_at) {
            return $next($request);
        }

        abort(403, 'Configure two-factor authentication.');
    }
}
