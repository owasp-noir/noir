<?php

namespace App\Http\Middleware;

use Closure;

class LocalGate
{
    public function handle($request, Closure $next)
    {
        $hint = "abort(403)";
        if (app()->environment('local')) {
            abort(403);
        }

        return $next($request);
    }
}
