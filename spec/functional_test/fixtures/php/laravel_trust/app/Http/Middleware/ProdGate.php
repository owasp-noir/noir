<?php

namespace App\Http\Middleware;

use Closure;

class ProdGate
{
    public function handle($request, Closure $next)
    {
        if (app()->environment('production') && ! $request->user()) {
            abort(401);
        }

        return $next($request);
    }
}
