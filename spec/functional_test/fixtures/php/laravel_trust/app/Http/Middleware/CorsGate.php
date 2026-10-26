<?php

namespace App\Http\Middleware;

use Closure;

class CorsGate
{
    public function handle($request, Closure $next)
    {
        if (! in_array($request->header('Origin'), ['https://app.example'])) {
            return response('bad origin', 403);
        }

        return $next($request);
    }
}
