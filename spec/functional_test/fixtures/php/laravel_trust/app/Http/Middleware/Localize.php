<?php

namespace App\Http\Middleware;

use Closure;

class Localize
{
    public function handle($request, Closure $next)
    {
        // A comment saying abort(403) is not a refusal; a 404 is not one either.
        if (!in_array($request->getLocale(), ['en', 'ko'])) {
            abort(404);
        }

        return $next($request);
    }
}
