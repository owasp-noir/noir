<?php

namespace App\Http\Middleware;

use Closure;

// A real credential check that a setting can switch off: guarded, with the note.
class ConfigAuthGate
{
    public function handle($request, Closure $next)
    {
        if (! config('app.require_login')) {
            return $next($request);
        }

        if (! $request->user()) {
            abort(401);
        }

        return $next($request);
    }
}
