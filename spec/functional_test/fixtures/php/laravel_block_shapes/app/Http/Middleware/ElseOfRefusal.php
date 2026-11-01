<?php
namespace App\Http\Middleware;

use Closure;

class ElseOfRefusal
{
    public function handle($request, Closure $next)
    {
        if (! $request->user()) {
            abort(401);
        } else {
            return $next($request);
        }
    }
}
